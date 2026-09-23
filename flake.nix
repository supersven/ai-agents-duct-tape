{
  description = "Pre-configured ai agent harnesses for specialized usages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixwrap.url = "github:rti/nixwrap";
    agent-skills.url = "github:Kyure-A/agent-skills-nix";
    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      llm-agents,
      nixwrap,
      agent-skills,
      superpowers,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (nixpkgs) lib;
        opencode = llm-agents.packages.${system}.opencode;
        harnessLib = import ./lib {
          inherit
            lib
            pkgs
            nixwrap
            opencode
            ;
        };
        superpowersHarness = import ./harnesses/superpowers.nix {
          inherit
            lib
            pkgs
            nixwrap
            opencode
            agent-skills
            superpowers
            ;
        };
        resolv = pkgs.writeText "resolv.conf" "nameserver 127.0.0.1\n";
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        packages.default = nixwrap.lib.${system}.wrap {
          package = opencode;
          wrapArgs = harnessLib.defaultWrapArgs;
        };
        packages.superpowers = superpowersHarness.package;

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.default ];
        };
        devShells.superpowers = superpowersHarness.devShell;

        apps = {
          update-types = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "update-types" ''
              export PATH=${
                lib.makeBinPath [
                  pkgs.curl
                  pkgs.python3
                  pkgs.nixfmt
                ]
              }:$PATH
              exec ${./scripts/update-types.sh}
            ''}/bin/update-types";
          };

          update-node-modules = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "update-node-modules" ''
              export PATH=${
                lib.makeBinPath [
                  pkgs.nodejs
                  pkgs.prefetch-npm-deps
                ]
              }:$PATH
              set -euo pipefail
              repo_root="$PWD"
              if [ ! -f "$repo_root/lib/node-modules/package-lock.json" ]; then
                echo "error: run from repo root (lib/node-modules/package-lock.json not found)" >&2
                exit 1
              fi
              version="${opencode.version}"
              tmp="$(mktemp -d)"
              trap 'rm -rf "$tmp"' EXIT
              cat > "$tmp/package.json" <<EOF
              { "name": "opencode-harness-deps", "version": "$version", "private": true,
                "dependencies": { "@opencode-ai/plugin": "$version" } }
              EOF
              cd "$tmp"
              npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
              cp package-lock.json "$repo_root/lib/node-modules/package-lock.json"
              echo "updated lib/node-modules/package-lock.json (opencode $version)"
              prefetch-npm-deps package-lock.json
            ''}/bin/update-node-modules";
          };
        };

        checks = {
          plugin-deps-are-current =
            pkgs.runCommand "plugin-deps-are-current"
              {
                nativeBuildInputs = [ pkgs.jq ];
                expected = opencode.version;
              }
              ''
                lockVersion=$(jq -r '.packages[""].version' ${./lib/node-modules/package-lock.json})
                depVersion=$(jq -r '.packages[""].dependencies["@opencode-ai/plugin"]' ${./lib/node-modules/package-lock.json})
                [ "$lockVersion" = "$expected" ] && [ "$depVersion" = "$expected" ] || {
                  echo "error: package-lock.json ($lockVersion/$depVersion) out of sync with opencode ($expected)" >&2
                  echo "run: nix run .#update-node-modules && update npmDepsHash in lib/mkHarness.nix" >&2
                  exit 1
                }
                echo ok > $out
              '';

          types-are-current =
            let
              configJson = pkgs.fetchurl {
                url = "https://opencode.ai/config.json";
                sha256 = "sha256-6MtuKHo4Uu40A/SAO+WtaxnblJSAN+qpZyElwzNCeSI=";
              };
            in
            pkgs.runCommand "types-are-current"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.nixfmt
                ];
              }
              ''
                python3 ${./scripts/generate-types.py} ${configJson} generated.nix
                diff -u ${./lib/types/generated.nix} generated.nix >&2
                echo ok > $out
              '';

          superpowers =
            pkgs.runCommand "check-superpowers"
              {
                nativeBuildInputs = [
                  pkgs.bubblewrap
                  pkgs.coreutils
                  pkgs.bash
                  superpowersHarness.package
                ];
                inherit resolv;
              }
              ''
                set -euo pipefail
                export HOME=$TMPDIR; mkdir -p $HOME

                # Why the outer bwrap: the pure nixwrap jail assumes a host-like root --
                # wrap.sh's shebang is `#!/usr/bin/env bash` and `-n` bind-mounts
                # /etc/resolv.conf, /etc/ssl and /etc/static/ssl. The nix build sandbox
                # strips all three (no /usr, empty read-only /etc). This bwrap is not a
                # second jail: it only recreates those host bits so the unmodified
                # upstream jail runs in the sandbox, verifying the shipped binary as-is.
                #
                # The sandbox root is read-only and has no /usr, so instead of
                # mounting it wholesale we start from an empty tmpfs root and bind in
                # the host bits the jail expects (/nix store, /bin/sh, /usr/bin/env,
                # the /etc network bits, /proc, /dev, writable $TMPDIR). /tmp is
                # required too: bwrap itself mounts a scratch tmpfs at /tmp during
                # its pivot_root setup, so the jail's bwrap needs it to exist.
                run() {
                  bwrap \
                    --die-with-parent \
                    --tmpfs / \
                    --ro-bind /nix /nix \
                    --dir /bin \
                    --ro-bind /bin/sh /bin/sh \
                    --dir /usr/bin \
                    --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env \
                    --ro-bind /etc/passwd /etc/passwd \
                    --ro-bind /etc/group /etc/group \
                    --ro-bind /etc/hosts /etc/hosts \
                    --dir /etc/ssl --dir /etc/static/ssl \
                    --ro-bind $resolv /etc/resolv.conf \
                    --dir /tmp \
                    --proc /proc --dev /dev \
                    --bind $TMPDIR $TMPDIR \
                    --setenv HOME $TMPDIR \
                    --setenv PATH ${
                      lib.makeBinPath [
                        pkgs.bubblewrap
                        pkgs.coreutils
                        pkgs.bash
                      ]
                    } \
                    --chdir $TMPDIR \
                    -- "$@"
                }

                run ${superpowersHarness.package}/bin/opencode debug config > config.json
                grep -q '"edit": "ask"' config.json
                grep -q '"bash": "ask"' config.json
                grep -q 'rules/test-rule.md' config.json
                grep -q '"test-agent"' config.json
                grep -q '"test-command"' config.json

                run ${superpowersHarness.package}/bin/opencode debug skill > skills.json
                grep -q 'test-skill' skills.json
                grep -q 'brainstorming' skills.json

                run ${superpowersHarness.package}/bin/opencode debug agent plan > agent.json
                grep -q '"test-tool"' agent.json

                echo ok > $out
              '';

          formatting = treefmtEval.config.build.check self;
        };
      }
    );
}
