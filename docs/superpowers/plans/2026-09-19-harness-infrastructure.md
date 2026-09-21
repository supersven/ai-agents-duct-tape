# Harness Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the harness-creating infrastructure for this flake: typed Nix part modules that compose into pre-configured opencode agents ("harnesses"), with a generator that derives Nix types from opencode's config schema.

**Architecture:** Harness parts are standard nixpkgs modules (`lib.evalModules`) with typed options for `opencode` config, `skills`, `tools`, `agents`, `rules`, `commands`, and `dependencies`. A custom Python generator (`scripts/generate-types.py`) converts `https://opencode.ai/config.json` into `lib/types/generated.nix` (nixpkgs `types` + `options.Config` mkOption tree carrying descriptions). `mkHarness` evaluates the modules, writes `$out/opencode.json` + part dirs, ships `$out/node_modules/` (built by `buildNpmPackage` from the committed `lib/node-modules/package-lock.json`; `package.json` version derived from the opencode input), and wraps opencode via nixwrap with a `bin/opencode` wrapper script setting `OPENCODE_CONFIG`/`OPENCODE_CONFIG_DIR`.

**Tech Stack:** Nix, nixpkgs module system (`lib.modules.evalModules`), Python 3 (generator), agent-skills-nix (skill bundles), nixwrap (sandboxing), llm-agents.nix (opencode package), jq (build-time JSON), `opencode debug config` (verification).

**Spec:** `docs/superpowers/specs/2026-09-19-harness-infrastructure-design.md`

## Global Constraints

- Derived types come ONLY from the custom generator; `lib/types/generated.nix` is generated (never hand-edited). Regeneration via `nix run .#update-types`; `checks.types-are-current` verifies it's up to date.
- Every generated option uses `type = types.nullOr <T>` and `default = null` so `builtins.toJSON` of the merged config works; the harness builder strips nulls via `lib.filterAttrsRecursive (n: v: v != null)` before writing `opencode.json`.
- Object with `properties` + `additionalProperties` absent → strict submodule (rejects unknown keys, giving "Did you mean" errors). Object with `properties` + `additionalProperties` = schema → submodule with `freeformType = types.attrsOf T`. Bare object (no properties): `additionalProperties` = schema → `types.attrsOf T`, else `types.attrs`.
- `anyOf` → `types.oneOf`. External `$ref` (models.dev) co-occurs with `type: string` → `types.str`. Internal `$ref` → `types.<DefName>`. Array `prefixItems` → `types.listOf (types.oneOf [...])`.
- Part file names must match the schemas in `lib/types/schemas/{skill,agent,command}.json` (skill names allow `/` for nested IDs — a documented deviation from the opencode docs); frontmatter validated in the derivation build step via `yq` + `check-jsonschema` (not at eval — IFD). Lenient: agents/commands need no frontmatter (name from filename).
- Rules are NOT auto-discovered by opencode; the builder injects absolute store paths into `config.instructions`.
- `packages.default`/`devShells.default` stay as the current unconfigured wrap.
- Harness parts are separate modules per concern (one per file category) to exercise module merging.
- `wrapArgs` default: `-n -e COLORTERM -e ZELLIJ -e OPENCODE_CONFIG_DIR -e OPENCODE_CONFIG -w ~/.config/opencode -w ~/.cache/opencode -w ~/.local/share/opencode/ -w ~/.local/state/opencode/`. `-e OPENCODE_CONFIG` and `-e OPENCODE_CONFIG_DIR` always appended if absent.

---

### Task 1: Type generator script

**Files:**
- Create: `scripts/generate-types.py`
- Create: `scripts/update-types.sh`

**Interfaces:**
- Produces: `generate-types.py <config.json> <output.nix>` writes the generated Nix module. Later tasks import the result as `lib/types/generated.nix`.
- Produces: `update-types.sh` fetches `https://opencode.ai/config.json` and regenerates `lib/types/generated.nix` (used by `apps.update-types`).

- [ ] **Step 1: Write the generator**

```python
#!/usr/bin/env python3
"""Generate lib/types/generated.nix from opencode config.json.

Usage: generate-types.py <config.json> <output.nix>
"""
import json
import re
import sys

IDENT = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_'-]*$")


def nix_attr(name: str) -> str:
    """Quote attr name if not a bare Nix identifier."""
    return name if IDENT.match(name) else json.dumps(name)


def nix_str(s: str) -> str:
    return json.dumps(s)


def nix_literal(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return nix_str(v)
    if isinstance(v, (int, float)):
        return str(v)
    raise ValueError(f"unsupported literal: {v!r}")


def quote_comment(node: dict) -> str:
    d = node.get("description")
    return f" # {d}" if isinstance(d, str) else ""


class Gen:
    def __init__(self, schema: dict):
        self.defs = schema["$defs"]
        self.root = schema.get("$ref", "#/$defs/Config").rsplit("/", 1)[-1]

    def type_ref(self, ref: str) -> str:
        if ref.startswith("#/$defs/"):
            return f"generatedTypes.{nix_attr(ref.split('/')[-1])}"
        return "lib.types.str"  # external (models.dev)

    def type_expr(self, node: dict, ind: int = 0) -> str:
        if "$ref" in node:
            return self.type_ref(node["$ref"])
        if "enum" in node:
            vals = " ".join(nix_literal(v) for v in node["enum"])
            return f"lib.types.enum [ {vals} ]"
        t = node.get("type")
        if t == "string":
            return "lib.types.str"
        if t == "integer":
            return self.bounded("lib.types.int", node)
        if t == "number":
            return self.bounded("lib.types.float", node)
        if t == "boolean":
            return "lib.types.bool"
        if t == "array":
            if "prefixItems" in node:
                inner = " ".join(f"({self.type_expr(i, ind)})" for i in node["prefixItems"])
                return f"lib.types.listOf (lib.types.oneOf [ {inner} ])"
            items = node.get("items")
            if items:
                return f"lib.types.listOf ({self.type_expr(items, ind)})"
            return "lib.types.listOf lib.types.anything"
        if t == "object":
            return self.object_expr(node, ind)
        if "anyOf" in node:
            inner = " ".join(f"({self.type_expr(b, ind)})" for b in node["anyOf"])
            return f"lib.types.oneOf [ {inner} ]"
        if "oneOf" in node:
            inner = " ".join(f"({self.type_expr(b, ind)})" for b in node["oneOf"])
            return f"lib.types.oneOf [ {inner} ]"
        return "lib.types.anything"

    def bounded(self, base: str, node: dict) -> str:
        checks = []
        for k, op in (("minimum", ">="), ("maximum", "<="),
                      ("exclusiveMinimum", ">"), ("exclusiveMaximum", "<")):
            if k in node:
                checks.append(f"x {op} {node[k]}")
        if not checks:
            return base
        pred = "x: " + " && ".join(checks)
        return f"(lib.types.addCheck {base} ({pred}))"

    def object_expr(self, node: dict, ind: int = 0) -> str:
        p = "  " * ind
        props = node.get("properties", {})
        ap = node.get("additionalProperties")
        if not props:
            if isinstance(ap, dict):
                return f"lib.types.attrsOf ({self.type_expr(ap, ind)})"
            return "lib.types.attrs"
        lines = [f"{p}lib.types.submodule {{", f"{p}  options = {{"]
        for name, sub in props.items():
            lines.append(f"{p}    {nix_attr(name)} = {self.mkoption(sub, ind + 3)};{quote_comment(sub)}")
        lines.append(f"{p}  }};")
        if isinstance(ap, dict):
            lines.append(f"{p}  freeformType = lib.types.attrsOf ({self.type_expr(ap, ind + 1)});")
        lines.append(f"{p}}}")
        return "\n".join(lines)

    def mkoption(self, node: dict, ind: int) -> str:
        p = "  " * ind
        desc = node.get("description")
        d = f"{p}    description = {nix_str(desc)};\n" if isinstance(desc, str) else ""
        return (
            p + "mkOption {\n"
            + f"{p}    type = lib.types.nullOr ({self.type_expr(node, ind)});\n"
            + f"{p}    default = null;\n"
            + d
            + p + "  }"
        )

    def root_options(self) -> str:
        root = self.defs[self.root]
        props = root.get("properties", {})
        lines = ["{"]
        for name, sub in props.items():
            lines.append(f"  {nix_attr(name)} = {self.mkoption(sub, 1)};{quote_comment(sub)}")
        lines.append("}")
        return "\n".join(lines)

    def def_expr(self, name: str) -> str:
        if name == self.root:
            root = self.defs[self.root]
            ap = root.get("additionalProperties")
            free = f"\n      freeformType = lib.types.attrsOf ({self.type_expr(ap, 3)});" if isinstance(ap, dict) else ""
            return f"lib.types.submodule {{\n      options = options.{nix_attr(self.root)};{free}\n    }}"
        return self.type_expr(self.defs[name], 2)

    def generate(self) -> str:
        out = [
            "{ lib }:",
            "let",
            "  mkOption = lib.mkOption;",
            "  options = {",
            f"    {nix_attr(self.root)} = {self.root_options()};",
            "  };",
            "  generatedTypes = {",
        ]
        for name in self.defs:
            out.append(f"    {nix_attr(name)} = {self.def_expr(name)};")
        out.append("  };")
        out.append("in")
        out.append("{")
        out.append("  inherit generatedTypes options;")
        out.append("  types = generatedTypes;")
        out.append("}")
        return "\n".join(out) + "\n"


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: generate-types.py <config.json> <output.nix>")
    with open(sys.argv[1]) as f:
        schema = json.load(f)
    with open(sys.argv[2], "w") as f:
        f.write(Gen(schema).generate())


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Write the update script**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://opencode.ai/config.json" -o "$tmp"
python3 "$repo_root/scripts/generate-types.py" "$tmp" "$repo_root/lib/types/generated.nix"
```

- [ ] **Step 3: Generate the types file**

Run: `mkdir -p lib/types && python3 scripts/generate-types.py /tmp/opencode/config.json lib/types/generated.nix`
Expected: `lib/types/generated.nix` created, containing `rec { types = { ... }; options = { Config = { ... }; }; }` with every def name and root `Config` wrapping `options.Config`.

- [ ] **Step 4: Verify the generated file evaluates and behaves correctly**

Run: `nix-instantiate --eval --strict --expr 'let g = import ./lib/types/generated.nix { lib = (import <nixpkgs> {}).lib; }; in builtins.typeOf g.types.Config'`
Expected: `"option-type"` (no eval error, no infinite recursion).

Then run the module-system behavior check:

```bash
cat > /tmp/opencode/harness-eval-test.nix <<'EOF'
{ lib }:
let
  g = import /home/sven/src/ai-agents-tuct-tape/lib/types/generated.nix { inherit lib; };
  eval = lib.evalModules {
    modules = [
      { options.opencode = lib.mkOption { type = g.types.Config; }; }
      { opencode.permission.edit = "ask"; }
      { opencode.permission.bash = "allow"; }
      { opencode.agent.custom-agent.mode = "subagent"; }
      { opencode.agent.custom-agent.model = "anthropic/claude"; }
      { opencode.lsp = true; }
      { opencode.plugin = [ "opencode-plugin" ]; }
    ];
  };
in
builtins.toJSON (lib.filterAttrsRecursive (n: v: v != null) eval.config.opencode)
EOF
nix-instantiate --eval --strict --expr 'let f = import /tmp/opencode/harness-eval-test.nix; in f { lib = (import <nixpkgs> {}).lib; }'
```
Expected: JSON with `permission.edit=ask`, `permission.bash=allow` (two parts deep-merge into one object), `agent.custom-agent` (freeform custom agent), `lsp=true`, `plugin`; no error. Also confirm unknown-key rejection: `opencode.agent.bob.bogus = "x"` errors with "Did you mean ... bob.mode".

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-types.py scripts/update-types.sh lib/types/generated.nix
git commit -m "feat: generate opencode config types from schema"
```

---

### Task 2: Domain types

**Files:**
- Create: `lib/types/domain.nix`

**Interfaces:**
- Consumes: `generated.types.Config` / `generated.options.Config` from `lib/types/generated.nix`.
- Produces: `configType`, `skill`, `tool`, `agent`, `rule`, `command`, `harnessPart` — used by `lib/modules.nix` and `lib/default.nix`.

- [ ] **Step 1: Write the file**

```nix
{ lib, generated }:
{
  configType = generated.types.Config;
  skill = lib.types.path;
  tool = lib.types.path;
  agent = lib.types.path;
  rule = lib.types.path;
  command = lib.types.path;
  harnessPart = lib.types.submodule {
    options = {
      config = lib.mkOption { type = lib.types.submodule { options = generated.options.Config; }; };
      skills = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      tools = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      agents = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      rules = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      commands = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      dependencies = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
    };
  };
}
```

- [ ] **Step 2: Verify it evaluates**

Run: `nix-instantiate --eval --strict --expr 'let g = import ./lib/types/generated.nix { lib = (import <nixpkgs> {}).lib; }; d = import ./lib/types/domain.nix { lib = (import <nixpkgs> {}).lib; generated = g; }; in d.configType.name + "|" + d.skill.name'`
Expected: `"submodule|path"` — no error.

- [ ] **Step 3: Commit**

```bash
git add lib/types/domain.nix
git commit -m "feat: add domain types for harness parts"
```
---

### Task 3: Harness module system

**Files:**
- Create: `lib/modules.nix`

**Interfaces:**
- Consumes: `generated.options.Config` from `lib/types/generated.nix`, `domain.*` from `lib/types/domain.nix`.
- Produces: `evalHarness { modules }` returning `{ config; skills; tools; agents; rules; commands; dependencies; }` (the merged part record, `config` typed by the derived Config).

- [ ] **Step 1: Write the file**

```nix
{ lib, generated, domain }:
{
  evalHarness = { modules }:
    let
      base = {
        options = {
          opencode = lib.mkOption {
            type = lib.types.submodule { options = generated.options.Config; };
            description = "opencode configuration fragment";
          };
          skills = lib.mkOption { type = lib.types.listOf domain.skill; default = [ ]; };
          tools = lib.mkOption { type = lib.types.listOf domain.tool; default = [ ]; };
          agents = lib.mkOption { type = lib.types.listOf domain.agent; default = [ ]; };
          rules = lib.mkOption { type = lib.types.listOf domain.rule; default = [ ]; };
          commands = lib.mkOption { type = lib.types.listOf domain.command; default = [ ]; };
          dependencies = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
        };
      };
      res = lib.evalModules {
        modules = [ base ] ++ modules;
      };
    in
    {
      config = res.config.opencode;
      skills = res.config.skills;
      tools = res.config.tools;
      agents = res.config.agents;
      rules = res.config.rules;
      commands = res.config.commands;
      dependencies = res.config.dependencies;
    };
}
```

- [ ] **Step 2: Verify merging of separate part modules**

Run:

```bash
cat > /tmp/opencode/modules-test.nix <<'EOF'
{ lib }:
let
  generated = import /home/sven/src/ai-agents-tuct-tape/lib/types/generated.nix { inherit lib; };
  domain = import /home/sven/src/ai-agents-tuct-tape/lib/types/domain.nix { inherit lib generated; };
  evalHarness = (import /home/sven/src/ai-agents-tuct-tape/lib/modules.nix { inherit lib generated domain; }).evalHarness;
in
evalHarness {
  modules = [
    { opencode.permission.edit = "ask"; }
    { opencode.permission.bash = "allow"; }
    { opencode.agent.custom-agent.mode = "subagent"; }
    { skills = [ /tmp/opencode/modtest/skill-a ]; }
    { skills = [ /tmp/opencode/modtest/skill-b ]; }
    { tools = [ /tmp/opencode/modtest/tool-a.ts ]; }
    { dependencies = [ (import <nixpkgs> {}).hello ]; }
  ];
}
EOF
mkdir -p /tmp/opencode/modtest/skill-a /tmp/opencode/modtest/skill-b
touch /tmp/opencode/modtest/tool-a.ts
nix-instantiate --eval --strict --expr 'let f = import /tmp/opencode/modules-test.nix; r = f { lib = (import <nixpkgs> {}).lib; }; in builtins.toString (builtins.length r.skills) + ":" + builtins.toString (builtins.length r.tools) + ":" + builtins.toString (builtins.length r.dependencies)' 2>&1 | tail -3
```
Expected: `2:1:1` (skills from two modules merge; tools and dependencies each merge from one). No eval error.

- [ ] **Step 3: Commit**

```bash
git add lib/modules.nix
git commit -m "feat: evalHarness via nixpkgs module system"
```

---

### Task 4: nixwrap wrapper builder

**Files:**
- Create: `lib/wrap.nix`

**Interfaces:**
- Consumes: `nixwrap.lib.${system}.wrap`, `opencode` package, `lib`, `pkgs`.
- Produces: `{ defaultWrapArgs; wrap = { wrapArgs ? defaultWrapArgs } -> derivation }` — the nixwrapped opencode (used by `mkHarness` and `packages.default`).

- [ ] **Step 1: Write the file**

```nix
{ lib, pkgs, nixwrap, opencode }:
let
  defaultWrapArgs =
    "-n -e COLORTERM -e ZELLIJ -e OPENCODE_CONFIG_DIR -e OPENCODE_CONFIG"
    + " -w ~/.config/opencode -w ~/.cache/opencode"
    + " -w ~/.local/share/opencode/ -w ~/.local/state/opencode/";
in
{
  inherit defaultWrapArgs;
  wrap = { wrapArgs ? defaultWrapArgs }:
    let
      hasConfig = lib.hasInfix "-e OPENCODE_CONFIG " wrapArgs;
      hasDir = lib.hasInfix "-e OPENCODE_CONFIG_DIR " wrapArgs;
      args = wrapArgs
        + lib.optionalString (!hasConfig) " -e OPENCODE_CONFIG"
        + lib.optionalString (!hasDir) " -e OPENCODE_CONFIG_DIR";
    in
    nixwrap.lib.${pkgs.system}.wrap {
      package = opencode;
      wrapArgs = args;
    };
}
```

- [ ] **Step 2: Verify the wrapArgs default and flag appending**

Run: `nix-instantiate --eval --strict --expr 'let w = import ./lib/wrap.nix { lib = (import <nixpkgs> {}).lib; pkgs = import <nixpkgs> {}; nixwrap = { lib = { x86_64-linux = { wrap = { wrapArgs ? "" }: { name = "wrapped"; inherit wrapArgs; }; }; }; }; opencode = {}; }; in w.defaultWrapArgs'` 2>&1 | tail -2
Expected: the default wrapArgs string. Also verify appending: call `w.wrap { wrapArgs = "-n"; }` and confirm the result's `wrapArgs` contains `-e OPENCODE_CONFIG` and `-e OPENCODE_CONFIG_DIR`.

- [ ] **Step 3: Commit**

```bash
git add lib/wrap.nix
git commit -m "feat: nixwrap wrapper builder for harnesses"
```

---

### Task 5: Harness derivation builder

**Files:**
- Create: `lib/mkHarness.nix`

**Interfaces:**
- Consumes: `evalHarness` (from `lib/modules.nix`), `wrap` (from `lib/wrap.nix`), `pkgs`, `lib`.
- Produces: `mkHarness { name; modules; wrapArgs }` returning `{ package; devShell; config }`.

- [ ] **Step 1: Write the builder**

```nix
{ lib, pkgs, evalHarness, wrap, defaultWrapArgs, opencode }:
let
  # node_modules for custom tools via buildNpmPackage; package.json generated
  # inline from the opencode input (version can't drift), lockfile committed,
  # npmDepsHash pins the transitive closure. Refresh: nix run .#update-node-modules.
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
      wrapped = wrap { wrapArgs = if wrapArgs == null then defaultWrapArgs else wrapArgs; };
      depsPath = lib.makeBinPath parts.dependencies;
    in
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "configJSON" ];
        inherit configJSON nodeModules;
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

        # node_modules for custom tools (@opencode-ai/plugin + transitive deps)
        cp -r $nodeModules/node_modules $out/node_modules

        # frontmatter validation (build-time, IFD-safe), via declarative JSON
        # schemas in lib/types/schemas/ (yq + check-jsonschema). Lenient: agents
        # and commands derive their name from the filename, so missing
        # frontmatter is fine; skills must declare `name`.
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
}
```

- [ ] **Step 2: Build a minimal harness**

Run:

```bash
mkdir -p /tmp/opencode/harness-min/skills/demo
cat > /tmp/opencode/harness-min/skills/demo/SKILL.md <<'MD'
---
name: demo
description: "A demo skill"
---
Body.
MD
nix-instantiate --eval --strict --expr 'let g = import ./lib/types/generated.nix { lib = (import <nixpkgs> {}).lib; }; d = import ./lib/types/domain.nix { lib = (import <nixpkgs> {}).lib; generated = g; }; m = import ./lib/modules.nix { lib = (import <nixpkgs> {}).lib; generated = g; domain = d; }; w = import ./lib/wrap.nix { lib = (import <nixpkgs> {}).lib; pkgs = import <nixpkgs> {}; nixwrap = { lib = { x86_64-linux = { wrap = { wrapArgs ? "" }: { name = "wrapped"; inherit wrapArgs; }; }; }; }; opencode = {}; }; h = import ./lib/mkHarness.nix { lib = (import <nixpkgs> {}).lib; pkgs = import <nixpkgs> {}; evalHarness = m.evalHarness; wrap = w.wrap; defaultWrapArgs = w.defaultWrapArgs; }; in builtins.typeOf (h.mkHarness { name = "min"; modules = [ { opencode.permission.edit = "ask"; skills = [ /tmp/opencode/harness-min/skills/demo ]; } ]; })' 2>&1 | tail -3
```
Expected: `"derivation"` — the harness derivation evaluates without error.

- [ ] **Step 3: Build the minimal harness and inspect output**

Run: `nix build --impure --expr 'let g = import /home/sven/src/ai-agents-tuct-tape/lib/types/generated.nix { lib = (import <nixpkgs> {}).lib; }; d = import /home/sven/src/ai-agents-tuct-tape/lib/types/domain.nix { lib = (import <nixpkgs> {}).lib; generated = g; }; m = import /home/sven/src/ai-agents-tuct-tape/lib/modules.nix { lib = (import <nixpkgs> {}).lib; generated = g; domain = d; }; w = import /home/sven/src/ai-agents-tuct-tape/lib/wrap.nix { lib = (import <nixpkgs> {}).lib; pkgs = import <nixpkgs> {}; nixwrap = { lib = { x86_64-linux = { wrap = { wrapArgs ? "" }: { name = "wrapped"; inherit wrapArgs; }; }; }; }; opencode = {}; }; h = import /home/sven/src/ai-agents-tuct-tape/lib/mkHarness.nix { lib = (import <nixpkgs> {}).lib; pkgs = import <nixpkgs> {}; evalHarness = m.evalHarness; wrap = w.wrap; defaultWrapArgs = w.defaultWrapArgs; }; in h.mkHarness { name = "min"; modules = [ { opencode.permission.edit = "ask"; skills = [ /tmp/opencode/harness-min/skills/demo ]; } ]; }'`
Expected: build succeeds. Then `ls result/skills/demo/SKILL.md result/opencode.json result/bin/opencode` and `jq . result/opencode.json` shows `{"permission":{"edit":"ask"}}` (nulls stripped, no trailing-null noise).

- [ ] **Step 4: Commit**

```bash
git add lib/mkHarness.nix
git commit -m "feat: mkHarness builds opencode harness derivation"
```
---

### Task 6: Public API and flake wiring

**Files:**
- Create: `lib/default.nix`
- Modify: `flake.nix`

**Interfaces:**
- Consumes: `lib/types/domain.nix`, `lib/modules.nix`, `lib/wrap.nix`, `lib/mkHarness.nix`, `nixwrap`, `opencode`, `pkgs`.
- Produces: `lib/default.nix` exposing `{ evalHarness; wrap; mkHarness; defaultWrapArgs; }`; flake outputs `apps.update-types` + `checks.types-are-current`. (`packages.superpowers`/`devShells.superpowers` come in Task 7.)

- [ ] **Step 1: Write `lib/default.nix`**

```nix
{ lib, pkgs, nixwrap, opencode }:
let
  generated = import ./types/generated.nix { inherit lib; };
  domain = import ./types/domain.nix { inherit lib generated; };
  modules = import ./modules.nix { inherit lib generated domain; };
  wrapLib = import ./wrap.nix { inherit lib pkgs nixwrap opencode; };
  mkHarnessLib = import ./mkHarness.nix {
    inherit lib pkgs;
    evalHarness = modules.evalHarness;
    wrap = wrapLib.wrap;
    inherit (wrapLib) defaultWrapArgs;
  };
in
{
  inherit generated domain modules;
  inherit (wrapLib) defaultWrapArgs;
  evalHarness = modules.evalHarness;
  wrap = wrapLib.wrap;
  mkHarness = mkHarnessLib.mkHarness;
}
```

- [ ] **Step 2: Update `flake.nix`**

Add the `superpowers` input and the harness wiring, keeping `packages.default`/`devShells.default` as the current unconfigured wrap:

```nix
{
  description = "Pre-configured ai agent harnesses for specialized usages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixwrap.url = "github:rti/nixwrap";
    agent-skills.url = "github:Kyure-A/agent-skills-nix";
    superpowers.url = "github:obra/superpowers";
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
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        opencode = llm-agents.packages.${system}.opencode;
        harnessLib = import ./lib {
          inherit lib pkgs nixwrap opencode;
        };
        superpowersHarness = import ./harnesses/superpowers.nix {
          inherit lib pkgs nixwrap opencode agent-skills superpowers;
        };
      in
      {
        packages.default = harnessLib.wrap { };
        packages.superpowers = superpowersHarness.package;

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.default ];
        };
        devShells.superpowers = superpowersHarness.devShell;

        apps.update-types = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "update-types" ''
            export PATH=${lib.makeBinPath [ pkgs.curl pkgs.python3 ]}:$PATH
            exec ${./scripts/update-types.sh}
          ''}/bin/update-types";
        };

        checks.types-are-current = pkgs.runCommand "types-are-current"
          {
            nativeBuildInputs = [ pkgs.curl pkgs.python3 ];
          }
          ''
            tmp=$(mktemp -d)
            curl -fsSL https://opencode.ai/config.json -o "$tmp/config.json"
            python3 ${./scripts/generate-types.py} "$tmp/config.json" "$tmp/generated.nix"
            diff -u ${./lib/types/generated.nix} "$tmp/generated.nix" >&2
            echo ok > $out
          '';
      }
    );
}
```

Note: `harnesses/superpowers.nix` is created in Task 7, so `nix flake check` will not fully pass until Task 7 lands. `checks.types-are-current` itself only needs `scripts/` + `lib/types/generated.nix`.

- [ ] **Step 3: Verify `apps.update-types` regenerates identically**

Run: `nix run .#update-types` then `git diff --stat lib/types/generated.nix`
Expected: no diff (generated file already current). If there IS a diff, the generator has a bug — fix before continuing.

- [ ] **Step 4: Verify `checks.types-are-current`**

Run: `nix flake check` 2>&1 | tail -5
Expected: `checks.types-are-current` passes.

- [ ] **Step 5: Commit**

```bash
git add lib/default.nix flake.nix flake.lock
git commit -m "feat: wire lib API and update-types app/check into flake"
```

---

### Task 7: Example harness part modules and files

**Files:**
- Create: `harnesses/superpowers.nix`
- Create: `harnesses/parts/base.nix`
- Create: `harnesses/parts/superpowers.nix`
- Create: `harnesses/parts/skill.nix`
- Create: `harnesses/parts/tool.nix`
- Create: `harnesses/parts/agent.nix`
- Create: `harnesses/parts/command.nix`
- Create: `harnesses/parts/rule.nix`
- Create: `skills/local-demo/SKILL.md`
- Create: `tools/hello.ts`
- Create: `agents/reviewer.md`
- Create: `commands/status.md`
- Create: `rules/team.md`

**Interfaces:**
- Consumes: `harnessLib.mkHarness`, `agent-skills.lib.agent-skills`, `superpowers` flake input.
- Produces: the `superpowers` harness (built in Task 8's check).

Rationale: one part module per concern (base config, superpowers bundle, local skill, tool, agent, command, rule) so module **merging** is genuinely exercised: base sets `permission.edit`, rule part sets `permission.bash` (same object, different keys — must deep-merge); superpowers part and skill part both contribute to `skills`.

- [ ] **Step 1: Write the part files**

`skills/local-demo/SKILL.md`:

```markdown
---
name: local-demo
description: "A tiny local skill to exercise the skills copy channel"
---

Always summarize your work in three bullet points.
```

`tools/hello.ts`:

```ts
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Say hello to the world",
  args: { name: tool.schema.string() },
  async execute(args) {
    return `hello ${args.name}`
  },
})
```

`agents/reviewer.md`:

```markdown
---
mode: subagent
description: "Review code changes for issues"
---

Review the current changes and report issues concisely.
```

`commands/status.md`:

```markdown
---
description: "Show the current git status"
---

Show the git status of the current repository.
```

`rules/team.md`:

```markdown
Follow the team conventions when writing code.
```

- [ ] **Step 2: Write the part modules**

`harnesses/parts/base.nix`:

```nix
{ lib, ... }:
{
  config.opencode.permission.edit = "ask";
}
```

`harnesses/parts/superpowers.nix`:

```nix
{ pkgs, lib, agent-skills, superpowers }:
let
  agentLib = agent-skills.lib.agent-skills;
  sources = {
    superpowers = {
      path = superpowers;
      subdir = "skills";
    };
  };
  catalog = agentLib.discoverCatalog sources;
  allowlist = agentLib.allowlistFor {
    inherit catalog sources;
    enableAll = true;
  };
  selection = agentLib.selectSkills {
    inherit catalog sources allowlist;
  };
  bundle = agentLib.mkBundle {
    inherit pkgs;
    selection = selection;
  };
in
{
  config.skills = [ bundle ];
}
```

`harnesses/parts/skill.nix`:

```nix
{
  config.skills = [ ./../../skills/local-demo ];
}
```

`harnesses/parts/tool.nix`:

```nix
{
  config.tools = [ ./../../tools/hello.ts ];
}
```

`harnesses/parts/agent.nix`:

```nix
{
  config.agents = [ ./../../agents/reviewer.md ];
}
```

`harnesses/parts/command.nix`:

```nix
{
  config.commands = [ ./../../commands/status.md ];
}
```

`harnesses/parts/rule.nix`:

```nix
{
  config.opencode.permission.bash = "ask";
  config.rules = [ ./../../rules/team.md ];
}
```

- [ ] **Step 3: Write the harness composition**

`harnesses/superpowers.nix`:

```nix
{ lib, pkgs, nixwrap, opencode, agent-skills, superpowers }:
let
  harnessLib = import ../lib {
    inherit lib pkgs nixwrap opencode;
  };
  harness = harnessLib.mkHarness {
    name = "superpowers";
    modules = [
      (import ./parts/base.nix { inherit lib; })
      (import ./parts/superpowers.nix { inherit pkgs lib agent-skills superpowers; })
      (import ./parts/skill.nix)
      (import ./parts/tool.nix)
      (import ./parts/agent.nix)
      (import ./parts/command.nix)
      (import ./parts/rule.nix)
    ];
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
}
```

`nixwrap` and `opencode` are passed explicitly from the flake (no `import ../flake.nix`). Update Task 6's flake call accordingly:

- [ ] **Step 4: Build the harness**

Run: `nix build .#packages.superpowers`
Expected: builds. Then verify:
- `result/opencode.json` contains `permission.edit=ask` AND `permission.bash=ask` (merged from two parts) and `instructions` includes `result/rules/team.md`.
- `result/skills/` contains `local-demo` and the superpowers bundle skills (e.g. `brainstorming`).
- `result/tools/hello.ts`, `result/agents/reviewer.md`, `result/commands/status.md` exist.
- `result/node_modules/@opencode-ai/plugin/package.json` exists.

- [ ] **Step 5: Commit**

```bash
git add harnesses/ skills/local-demo tools/hello.ts agents/reviewer.md commands/status.md rules/team.md flake.nix flake.lock
git commit -m "feat: superpowers example harness with per-concern part modules"
```

---

### Task 8: Automated harness checks

**Files:**
- Modify: `flake.nix` (add `checks.superpowers`)

**Interfaces:**
- Consumes: the `superpowers` harness package.
- Produces: `checks.superpowers` — a derivation that runs the wrapped `opencode debug config` / `debug skill` / `debug agent` inside the build sandbox and asserts the harness loads.

Verified facts the check relies on (from research): bwrap runs inside a nix build sandbox when `HOME` is writable; `opencode debug config` prints merged config (instructions/rules, permissions, agents, commands); `opencode debug skill` lists skills; `opencode debug agent <name>` lists tools (proving the custom tool loads via `$out/node_modules/@opencode-ai/plugin`).

- [ ] **Step 1: Add `checks.superpowers` to `flake.nix`**

```nix
checks.superpowers = pkgs.runCommand "check-superpowers"
  {
    nativeBuildInputs = [ superpowersHarness.package ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR
    mkdir -p $HOME

    opencode debug config > config.json
    grep -q '"edit": "ask"' config.json
    grep -q '"bash": "ask"' config.json
    grep -q 'rules/team.md' config.json
    grep -q '"reviewer"' config.json
    grep -q '"status"' config.json

    opencode debug skill > skills.json
    grep -q 'local-demo' skills.json
    grep -q 'brainstorming' skills.json

    opencode debug agent plan > agent.json
    grep -q '"hello"' agent.json

    echo ok > $out
  '';
```

Where `superpowersHarness` is the value bound in `flake.nix` (Task 6 Step 2). Add `checks.superpowers = ...` inside the `flake-utils.lib.eachDefaultSystem` attrset.

- [ ] **Step 2: Run the full flake check**

Run: `nix flake check` 2>&1 | tail -8
Expected: all checks pass — `types-are-current` and `superpowers` (build + `debug config`/`debug skill`/`debug agent` assertions).

If `opencode debug agent plan` fails with a model/provider error, set a model in the harness base part (`config.opencode.model = "openai/gpt-4o";`) so `debug agent` resolves a model without credentials, then rebuild.

- [ ] **Step 3: Manual verification**

Run: `nix develop .#superpowers --command opencode` and confirm the superpowers skills appear in the skill picker, the custom `hello` tool loads, and the `reviewer` agent / `status` command are available.

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat: verify superpowers harness via opencode debug commands"
```

---

## Self-review notes

- Spec coverage: generator (Task 1) maps the full table incl. `freeformType`/strict submodules, `oneOf`, `prefixItems`, bounds, external `$ref`; `options.Config` descriptions preserved (Task 1 Step 4 checks the "Did you mean" error). Domain types (Task 2). Module system with typed options + output record incl. `agents`/`dependencies` (Task 3). wrapArgs defaults + `-e` appending (Task 4). Derivation builder with `$out/opencode.json`, part dirs, rules injection into `instructions`, `node_modules` for `@opencode-ai/plugin`, `bin/opencode` wrapper, frontmatter validation (Task 5). flake wiring: `apps.update-types`, `checks.types-are-current`, `packages.superpowers`/`devShells.superpowers`, `packages.default` unchanged (Tasks 6-7). Example harness with per-concern part modules incl. agent-skills bundle (Task 7). Verification via `nix flake check` + manual (Task 8).
- Placeholder scan: no TBDs; every code step has concrete content. The one judgment call (model for `debug agent`) has an explicit fallback.
- Type consistency: `evalHarness { modules }` returns `{ config; skills; tools; agents; rules; commands; dependencies; }` throughout; `mkHarness { name; modules; wrapArgs }`; `wrap { wrapArgs }`; `defaultWrapArgs`; `harnessPart` record fields match the builder's consumption (`parts.config`, `parts.skills`, ...).
- Verified during plan writing (empirically, against the real schema and opencode binary): the generator output evaluates and deep-merges correctly; unknown-key rejection produces the spec's exact "Did you mean" error; `nullOr` + `filterAttrsRecursive` serializes clean JSON; bwrap + `opencode debug config`/`debug skill`/`debug agent`/`agent list` run inside a nix build sandbox; the custom `tool()`-based tool loads via the shipped `@opencode-ai/plugin`; all Task 8 assertions match real `debug config`/`debug skill`/`debug agent` output.
- Known limitation: `types.oneOf` with two submodule branches (e.g. the `lsp` object branch) picks the first matching submodule, so per-language `lsp` object config is lossy. The boolean branch (`lsp = true`) works. Not needed by the example harness; acceptable per the spec's `anyOf → oneOf` mapping.