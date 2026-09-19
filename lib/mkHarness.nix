{ lib, pkgs, evalHarness, wrap, defaultWrapArgs }:
let
  pluginTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/plugin/-/plugin-1.18.31.tgz";
    sha256 = "0xvzdp7zq2z0279jf1r6gkj69b535c548jc64vwfzil6i7a082gd";
  };
  zodTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/zod/-/zod-4.1.8.tgz";
    sha256 = "0db67glfsfrbbh69s0x5qv9ld1kq718nl3n44bapkmk6vhrklghr";
  };
in
{
  mkHarness = { name, modules, wrapArgs ? null }:
    let
      parts = evalHarness { inherit modules; };
      cleanConfig = lib.filterAttrsRecursive (n: v: v != null) parts.config;
      configJSON = builtins.toJSON cleanConfig;
      wrapped = wrap { wrapArgs = if wrapArgs == null then defaultWrapArgs else wrapArgs; };
      depsPath = lib.makeBinPath parts.dependencies;
    in
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "configJSON" ];
        inherit configJSON pluginTgz zodTgz;
        skills = lib.concatStringsSep " " (map toString parts.skills);
        tools = lib.concatStringsSep " " (map toString parts.tools);
        agents = lib.concatStringsSep " " (map toString parts.agents);
        commands = lib.concatStringsSep " " (map toString parts.commands);
        rules = lib.concatStringsSep " " (map toString parts.rules);
        inherit wrapped depsPath;
      }
      ''
        set -euo pipefail
        mkdir -p $out/skills $out/tools $out/agents $out/commands $out/rules
        cp $configJSONPath $out/opencode.json

        for s in $skills; do cp -rL "$s" "$out/skills/"; done
        for t in $tools; do cp -L "$t" "$out/tools/"; done
        for a in $agents; do cp -L "$a" "$out/agents/"; done
        for c in $commands; do cp -L "$c" "$out/commands/"; done

        for r in $rules; do
          cp -L "$r" "$out/rules/"
        done

        # rules are NOT auto-discovered: inject absolute store paths into instructions
        if [ -n "$rules" ]; then
          extra=$(for f in $out/rules/*; do echo "$f"; done | jq -Rsc 'split("\n") | map(select(length > 0))')
          jq --argjson extra "$extra" '.instructions = ((.instructions // []) + $extra)' \
            $out/opencode.json > $out/opencode.json.tmp
          mv $out/opencode.json.tmp $out/opencode.json
        fi

        # @opencode-ai/plugin + zod for custom tools (npm install skipped in read-only store)
        mkdir -p $out/node_modules/@opencode-ai/plugin $out/node_modules/zod
        tar -xzf $pluginTgz -C $out/node_modules/@opencode-ai/plugin --strip-components=1
        tar -xzf $zodTgz -C $out/node_modules/zod --strip-components=1

        # frontmatter validation (build-time, IFD-safe)
        for f in $(find $out/skills -name SKILL.md) $out/agents/*.md $out/commands/*.md; do
          [ -f "$f" ] || continue
          name=$(awk 'NR==1 && $0=="---"{p=1;next} p&&$0=="---"{exit} p&&/^name:/{gsub(/^name:[[:space:]]*["'\'''\"]?/,"");gsub(/["'\'''\"]?[[:space:]]*$/,"");print;exit}' "$f")
          desc=$(awk 'NR==1 && $0=="---"{p=1;next} p&&$0=="---"{exit} p&&/^description:/{print;exit}' "$f")
          [ -n "$name" ] || { echo "error: missing name in $f" >&2; exit 1; }
          [ -n "$desc" ] || { echo "error: missing description in $f" >&2; exit 1; }
          echo "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' || { echo "error: invalid name '$name' in $f" >&2; exit 1; }
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
}

