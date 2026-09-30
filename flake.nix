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
        # Jailed semble: nixwrap-wrapped, one binary covers both the CLI and the
        # MCP server (semble auto-dispatches to MCP when no subcommand is given,
        # matching upstream's `uvx --from "semble[mcp]" semble`). Env vars from
        # the semble README (Storage): SEMBLE_CACHE_LOCATION, SEMBLE_MAX_FILE_BYTES,
        # SEMBLE_MODEL_NAME, HF_HOME. Writable: the default cache, HF model cache,
        # and the savings ledger. `-n` for first-run HF model download / git URLs.
        semble = nixwrap.lib.${system}.wrap {
          package = llm-agents.packages.${system}.semble;
          wrapArgs =
            "-n -e SEMBLE_CACHE_LOCATION -e SEMBLE_MAX_FILE_BYTES"
            + " -e SEMBLE_MODEL_NAME -e HF_HOME"
            + " -w ~/.cache/semble -w ~/.cache/huggingface -w ~/.semble";
        };
        vanillaDevHarness = import ./harnesses/vanilla-dev.nix {
          inherit
            lib
            pkgs
            nixwrap
            opencode
            agent-skills
            superpowers
            semble
            ;
        };
        resolv = pkgs.writeText "resolv.conf" "nameserver 127.0.0.1\n";
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        scriptsSrc = ./scripts;
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        packages.default = nixwrap.lib.${system}.wrap {
          package = opencode;
          wrapArgs = harnessLib.defaultWrapArgs;
        };
        packages.superpowers = superpowersHarness.package;
        packages.superpowers-llmaas = superpowersHarness.llmaas.package;
        packages.vanilla-dev = vanillaDevHarness.package;
        packages.vanilla-dev-llmaas = vanillaDevHarness.llmaas.package;

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.default ];
        };
        devShells.superpowers = superpowersHarness.devShell;
        devShells.superpowers-llmaas = superpowersHarness.llmaas.devShell;
        devShells.vanilla-dev = vanillaDevHarness.devShell;
        devShells.vanilla-dev-llmaas = vanillaDevHarness.llmaas.devShell;

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

          update-cloudtemple-models = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "update-cloudtemple-models" ''
              export PATH=${
                lib.makeBinPath [
                  pkgs.python3
                  pkgs.nixfmt
                ]
              }:$PATH
              exec ${scriptsSrc}/fetch-cloudtemple-models.py "$@"
            ''}/bin/update-cloudtemple-models";
          };

          cloudtemple-model-report = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "cloudtemple-model-report" ''
              export PATH=${lib.makeBinPath [ pkgs.python3 ]}:$PATH
              exec ${scriptsSrc}/cloudtemple-model-report.py "$@"
            ''}/bin/cloudtemple-model-report";
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
                  pkgs.jq
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
                jq -e '.permission.edit == "ask"' config.json >/dev/null
                jq -e '.permission.bash == "ask"' config.json >/dev/null
                jq -e 'any(.instructions[]; endswith("rules/test-rule.md"))' config.json >/dev/null
                jq -e '.agent | has("test-agent")' config.json >/dev/null
                jq -e '.command | has("test-command")' config.json >/dev/null

                run ${superpowersHarness.package}/bin/opencode debug skill > skills.json
                jq -e 'any(.[]; .name == "test-skill")' skills.json >/dev/null
                jq -e 'any(.[]; .name == "brainstorming")' skills.json >/dev/null

                run ${superpowersHarness.package}/bin/opencode debug agent plan > agent.json
                jq -e '.tools | has("test-tool")' agent.json >/dev/null

                echo ok > $out
              '';

          superpowers-llmaas =
            pkgs.runCommand "check-superpowers-llmaas"
              {
                nativeBuildInputs = [
                  pkgs.bubblewrap
                  pkgs.coreutils
                  pkgs.bash
                  pkgs.jq
                  superpowersHarness.llmaas.package
                ];
                inherit resolv;
              }
              ''
                set -euo pipefail
                export HOME=$TMPDIR; mkdir -p $HOME

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

                run ${superpowersHarness.llmaas.package}/bin/opencode debug config > config.json
                jq -e '.provider["cloud-temple"].npm == "@ai-sdk/openai-compatible"' config.json >/dev/null
                jq -e '.agent.build.model == "cloud-temple/qwen-coder-next:80b"' config.json >/dev/null
                jq -e '.agent.plan.model == "cloud-temple/qwen3.6:35b"' config.json >/dev/null
                jq -e '.agent.general.model == "cloud-temple/qwen3.6:27b"' config.json >/dev/null

                echo ok > $out
              '';

          vanilla-dev =
            pkgs.runCommand "check-vanilla-dev"
              {
                nativeBuildInputs = [
                  pkgs.bubblewrap
                  pkgs.coreutils
                  pkgs.bash
                  pkgs.jq
                  vanillaDevHarness.package
                ];
                inherit resolv semble;
              }
              ''
                set -euo pipefail
                export HOME=$TMPDIR; mkdir -p $HOME

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

                run ${vanillaDevHarness.package}/bin/opencode debug config > config.json
                jq -e '.permission.edit == "ask"' config.json >/dev/null
                jq -e '.mcp.semble.type == "local"' config.json >/dev/null
                jq -e --arg cmd "${semble}/bin/semble" \
                  'any(.mcp.semble.command[]; . == $cmd)' config.json >/dev/null
                jq -e 'any(.instructions[]; endswith("rules/semble.md"))' config.json >/dev/null
                jq -e 'any(.instructions[]; endswith("rules/be-concise.md"))' config.json >/dev/null
                jq -e '.agent | has("semble-search")' config.json >/dev/null

                run ${vanillaDevHarness.package}/bin/opencode debug skill > skills.json
                jq -e 'any(.[]; .name == "brainstorming")' skills.json >/dev/null

                run ${vanillaDevHarness.package}/bin/opencode debug agent semble-search > agent.json
                jq -e '.name == "semble-search"' agent.json >/dev/null
                jq -e '.mode == "subagent"' agent.json >/dev/null
                jq -e 'any(.permission[]; .permission == "bash" and .action == "allow")' agent.json >/dev/null

                echo ok > $out
              '';

          vanilla-dev-llmaas =
            pkgs.runCommand "check-vanilla-dev-llmaas"
              {
                nativeBuildInputs = [
                  pkgs.bubblewrap
                  pkgs.coreutils
                  pkgs.bash
                  pkgs.jq
                  vanillaDevHarness.llmaas.package
                ];
                inherit resolv;
              }
              ''
                set -euo pipefail
                export HOME=$TMPDIR; mkdir -p $HOME

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

                run ${vanillaDevHarness.llmaas.package}/bin/opencode debug config > config.json
                jq -e '.provider["cloud-temple"].npm == "@ai-sdk/openai-compatible"' config.json >/dev/null
                jq -e '.provider["cloud-temple"].options.baseURL == "https://api.ai.cloud-temple.com/v1"' config.json >/dev/null
                jq -e '.agent.build.model == "cloud-temple/qwen-coder-next:80b"' config.json >/dev/null
                jq -e '.agent.plan.model == "cloud-temple/qwen3.6:35b"' config.json >/dev/null
                jq -e '.agent.general.model == "cloud-temple/qwen3.6:27b"' config.json >/dev/null
                jq -e '.agent["semble-search"].model == "cloud-temple/qwen3.5:9b"' config.json >/dev/null

                echo ok > $out
              '';

          formatting = treefmtEval.config.build.check self;
        };
      }
    );
}
