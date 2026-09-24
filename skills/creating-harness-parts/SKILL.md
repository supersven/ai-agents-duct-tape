---
name: creating-harness-parts
description: Use when adding a new harness part module or composed harness to this repo (a tool/agent integration for opencode), wiring it into flake.nix, or adding a flake check for one. Also use when a part or harness exists but is missing its jail, check, or flake outputs.
---

# Creating Harness Parts and Harnesses

## Overview

A **harness part** is a typed Nix module contributing an opencode config fragment, part files (rules, tools, agents, skills, commands), and runtime dependencies. A **harness** composes parts via `mkHarness` into a self-contained opencode derivation. Output: `{ config, skills, tools, agents, rules, commands, dependencies }`.

## Part Module Shape

A part is a function of its inputs returning a module with **`config.`-prefixed keys only**:

```nix
{ semble }:   # derivations are passed in, not looked up from pkgs
{
  config.opencode.mcp.semble = {
    type = "local";
    command = [ "${semble}/bin/semble" ];
  };
  config.rules = [ ./../../rules/semble.md ];
  config.agents = [ ./../../agents/semble-search.md ];
  config.dependencies = [ semble ];
}
```

- `config.opencode.*` mirrors the schema in `lib/types/generated.nix`.
- `config.dependencies` is a module option: top-level `dependencies = [...]` fails.
- Part files live in top-level dirs, referenced `./../../<dir>/<file>`.

## Sourcing and Jailing

**Source the derivation from a flake input** (nixpkgs, llm-agents) in `flake.nix` — never fabricate a stand-in via `pkgs.extend`/overlay. Pass it through the harness into the part.

**Jail it** unless the opencode jail already covers the tool. Delegate documented env vars and writable state dirs:

```nix
semble = nixwrap.lib.${system}.wrap {
  package = llm-agents.packages.${system}.semble;
  wrapArgs =
    "-n -e SEMBLE_CACHE_LOCATION -e SEMBLE_MAX_FILE_BYTES"
    + " -e SEMBLE_MODEL_NAME -e HF_HOME"
    + " -w ~/.cache/semble -w ~/.cache/huggingface -w ~/.semble";
};
```

- `-n` network, `-e VAR` env var, `-w PATH` writable, `-r PATH` read-only.
- `~` IS expanded at runtime (wrapArgs interpolate into the wrapper script); don't "fix" to `$HOME`.
- The wrapped derivation is a normal derivation: pass it around, don't re-wrap in the part.
- nixwrap wraps **one executable per call** (`executable` arg, defaults to `package.pname`). Two binaries need a chain of two `wrap` calls, or one jailed binary if the CLI auto-dispatches to MCP on no subcommand (semble does). Set `executable` explicitly when the package lacks `pname` (e.g. `runCommand`).

## Harness Composition

```nix
harness = harnessLib.mkHarness {
  name = "vanilla-dev";
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/semble.nix { inherit semble; })
  ];
};
```

Return `{ package, devShell }` (see `harnesses/superpowers.nix`). `name` becomes the package/devShell/check attribute.

## flake.nix Wiring

`myHarness = import ./harnesses/my.nix { inherit lib pkgs nixwrap opencode; ... };` then `packages.my = myHarness.package;`, `devShells.my = myHarness.devShell;`, `checks.my = pkgs.runCommand ...`.

## Checks

Run `opencode debug config` / `debug skill` / `debug agent <name>` inside the outer-bwrap sandbox (copy `run()` + `resolv` from an existing check). Assert with **jq, position-independent**:

```bash
jq -e '.mcp.semble.type == "local"' config.json
jq -e --arg cmd "${semble}/bin/semble" 'any(.mcp.semble.command[]; . == $cmd)' config.json
jq -e 'any(.instructions[]; endswith("rules/semble.md"))' config.json
jq -e '.agent | has("semble-search")' config.json
```

Prefer `any(.x[]; …)` over `.x[0]`, `has()`/exact path over `contains()`. Add `pkgs.jq`. Dashed keys need bracket form (`.mcp["example-tool"]`). No skills → assert `type == "array"`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `dependencies` not under `config.` | `config.dependencies = [...]` |
| New files untracked | `git add` before `nix flake check` |
| Missing trailing newline | `nix fmt` |
| Looking up the tool from `pkgs` in the part | Pass the (wrapped) derivation in |
| Fabricating a package via overlay | Source from a flake input |
| `.mcp.x.command[0]` / grep | `any(.mcp.x.command[]; …)`, structure-aware |

## Verification

`git add -A && nix flake check` — all checks (incl. `checks.formatting`) must pass.