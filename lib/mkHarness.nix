{ lib, pkgs, nixwrap, opencode, evalHarness }:
let
  defaultWrapArgs =
    "-n -e COLORTERM -e ZELLIJ -e OPENCODE_CONFIG_DIR -e OPENCODE_CONFIG"
    + " -w ~/.config/opencode -w ~/.cache/opencode"
    + " -w ~/.local/share/opencode/ -w ~/.local/state/opencode/";
  prepareWrapArgs = wrapArgs:
    let
      hasConfig = lib.hasInfix "-e OPENCODE_CONFIG " wrapArgs;
      hasDir = lib.hasInfix "-e OPENCODE_CONFIG_DIR " wrapArgs;
    in
    wrapArgs
    + lib.optionalString (!hasConfig) " -e OPENCODE_CONFIG"
    + lib.optionalString (!hasDir) " -e OPENCODE_CONFIG_DIR";
  # @opencode-ai/plugin node_modules for custom tools, built via buildNpmPackage
  # from the committed package-lock.json. package.json is generated inline from
  # the opencode input (version = opencode.version), so it cannot drift; the
  # lockfile pins exact transitive versions and npmDepsHash prevents accidental
  # upgrades. Refresh via `nix run .#update-node-modules` (see README.md).
  packageJSON = pkgs.writeText "package.json" (builtins.toJSON {
    name = "opencode-harness-deps";
    version = opencode.version;
    private = true;
    dependencies = { "@opencode-ai/plugin" = opencode.version; };
  });
  nodeModulesSrc = pkgs.runCommand "opencode-harness-deps-src" { } ''
    mkdir -p $out
    cp ${packageJSON} $out/package.json
    cp ${./node-modules/package-lock.json} $out/package-lock.json
  '';
  nodeModules = pkgs.buildNpmPackage {
    pname = "opencode-harness-deps";
    version = opencode.version;
    src = nodeModulesSrc;
    npmDepsHash = "sha256-L7AqkgVrSrezS7jjVBqWevrypmmSX8Rs+CxUvmBZUCQ=";
    dontNpmBuild = true;
    installPhase = "mkdir -p $out/node_modules; cp -r node_modules/. $out/node_modules";
  };
in
{
  mkHarness = { name, modules, wrapArgs ? null }:
    let
      parts = evalHarness { inherit modules; };
      cleanConfig = lib.filterAttrsRecursive (n: v: v != null) parts.config;
      configJSON = builtins.toJSON cleanConfig;
      wrapped = nixwrap.lib.${pkgs.system}.wrap {
        package = opencode;
        wrapArgs = prepareWrapArgs (if wrapArgs == null then defaultWrapArgs else wrapArgs);
      };
      depsPath = lib.makeBinPath parts.dependencies;
      skillSchema = ./types/schemas/skill.json;
      agentSchema = ./types/schemas/agent.json;
      commandSchema = ./types/schemas/command.json;
      package = pkgs.runCommand name
        {
          nativeBuildInputs = [ pkgs.jq pkgs.yq-go pkgs.check-jsonschema ];
          passAsFile = [ "configJSON" ];
          inherit configJSON nodeModules skillSchema agentSchema commandSchema;
          # NOTE: do NOT use map toString here. Nix 2.34 does not register
          # flake-source paths as derivation inputs through toString; the
          # string coercion of a path preserves the derivation context, and
          # lib.concatStringsSep is what keeps that context alive so the
          # files actually reach the sandbox.
          skills = lib.concatStringsSep " " parts.skills;
          tools = lib.concatStringsSep " " parts.tools;
          agents = lib.concatStringsSep " " parts.agents;
          commands = lib.concatStringsSep " " parts.commands;
          rules = lib.concatStringsSep " " parts.rules;
          inherit wrapped depsPath;
        }
        ''
          set -euo pipefail
          mkdir -p $out/skills $out/tools $out/agents $out/commands $out/rules
          cp $configJSONPath $out/opencode.json
          printf 'node_modules\npackage.json\npackage-lock.json\nbun.lock\n.gitignore\n' > $out/.gitignore

          # Strip the ''${hash}- prefix (if present) from store paths: opencode
          # names custom tools/skills by their file basename, and the hash
          # prefix would leak into that name. [0-9a-z]{32} is the store hash
          # (base32), NOT [0-9a-f]{32}.
          copy_uniq() {
            src=$1; dir=$2
            dest="$out/$dir/$(basename "$src" | sed -E 's/^[0-9a-z]{32}-//')"
            if [ -e "$dest" ]; then
              echo "error: duplicate $dir name '$dest' from '$src'" >&2
              exit 1
            fi
            cp -rL "$src" "$dest"
          }
          for s in $skills; do copy_uniq "$s" skills; done
          for t in $tools; do copy_uniq "$t" tools; done
          for a in $agents; do copy_uniq "$a" agents; done
          for c in $commands; do copy_uniq "$c" commands; done
          for r in $rules; do copy_uniq "$r" rules; done

          # rules are NOT auto-discovered: inject absolute store paths into instructions
          if [ -n "$rules" ]; then
            extra=$(for f in $out/rules/*; do echo "$f"; done | jq -Rsc 'split("\n") | map(select(length > 0))')
            jq --argjson extra "$extra" '.instructions = ((.instructions // []) + $extra)' \
              $out/opencode.json > $out/opencode.json.tmp
            mv $out/opencode.json.tmp $out/opencode.json
          fi

          # node_modules for custom tools (@opencode-ai/plugin + transitive deps),
          # built via buildNpmPackage (see README.md "Updating node modules")
          cp -r $nodeModules/node_modules $out/node_modules

          # frontmatter validation (build-time, IFD-safe), via declarative JSON
          # schemas in lib/types/schemas/ instead of hand-rolled awk. Lenient by
          # design: agents/commands derive their name from the filename, so a
          # missing frontmatter is fine there; opencode's runtime loader is the
          # source of truth (see AGENTS.md). Skills must declare `name` — a skill
          # without one is silently dropped by opencode.
          validate_frontmatter() {
            f=$1; schema=$2; headerRequired=$3
            if head -1 "$f" | grep -q '^---$'; then
              tmp=$(mktemp)
              yq -f front-matter=process -o=json '.' "$f" > "$tmp"
              check-jsonschema --schemafile "$schema" "$tmp" >/dev/null || {
                echo "error: invalid frontmatter in $f" >&2; exit 1;
              }
              rm -f "$tmp"
            elif [ "$headerRequired" = headerRequired ]; then
              echo "error: missing frontmatter (no --- header) in $f" >&2; exit 1
            fi
          }
          for s in $out/skills/*; do
            [ -f "$s/SKILL.md" ] && validate_frontmatter "$s/SKILL.md" $skillSchema headerRequired
          done
          for a in $out/agents/*.md; do
            [ -f "$a" ] && validate_frontmatter "$a" $agentSchema headerNotRequired
          done
          for c in $out/commands/*.md; do
            [ -f "$c" ] && validate_frontmatter "$c" $commandSchema headerNotRequired
          done

          # bin/opencode wrapper
          mkdir -p $out/bin
          cat > $out/bin/opencode <<EOF
          #!/usr/bin/env bash
          export OPENCODE_CONFIG=$out/opencode.json
          export OPENCODE_CONFIG_DIR=$out
          export PATH=$depsPath:\$PATH
          exec $wrapped/bin/opencode "\$@"
          EOF
          chmod +x $out/bin/opencode
        ''
        // { passthru = { inherit parts; }; };
    in
    {
      inherit package;
      inherit (parts) config;
      devShell = pkgs.mkShell { packages = [ package ]; };
    };
  inherit defaultWrapArgs;
}
