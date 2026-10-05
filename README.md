# ai-agents-duct-tape

Nix flake providing pre-configured opencode harnesses for specialized usages.

## Haskell API search (hoogle MCP)

The `wire-server-haskell-dev` harness ships a `hoogle` MCP server, a
`hoogle-search` subagent, and a rule, giving opencode Haskell API lookup
against the Wire Hoogle instance (general instance opt-in).

- Harness: `nix develop .#wire-server-haskell-dev` (or
  `nix build .#wire-server-haskell-dev`).
- Standalone CLI: `nix build .#wire-hoogle-mcp` then
  `./result/bin/wire-hoogle-mcp query "map +base"`.
- No clone needed:
  `nix run github:supersven/ai-agents-duct-tape#wire-hoogle-mcp --` starts
  the MCP server. Add to Claude Code with
  `claude mcp add --scope user hoogle -- nix run github:supersven/ai-agents-duct-tape#wire-hoogle-mcp`
  (details in the MCP README below).
- Architecture, usage, and output format:
  [mcps/wire-hoogle-mcp/README.md](./mcps/wire-hoogle-mcp/README.md).

## Linting and formatting Nix code

Configured via [treefmt-nix](https://github.com/numtide/treefmt-nix)
(`treefmt.nix`):

- `nix fmt` — run nixfmt, deadnix and statix (as auto-fixers) on `.nix` files
- `nix flake check` — `checks.formatting` verifies the tree is already
  formatted/fixed (run in a sandbox git repo, fails on any diff)

`lib/types/generated.nix` is excluded from deadnix/statix (machine output;
statix flags its defensive parens) but stays nixfmt-formatted:
`generate-types.py` pipes its output through `nixfmt`, so regeneration keeps it
in sync. A direct `python3 scripts/generate-types.py …` run therefore needs
`nixfmt` on PATH (the `update-types` app provides it).

## Updating node modules (plugin deps)

`node_modules` for custom tools is built by `buildNpmPackage` from
`lib/node-modules/package-lock.json`; the `package.json` version is derived
from the opencode input at eval time, so it cannot drift. When the opencode
input bumps:

1. `nix run .#update-node-modules` — regenerates `package-lock.json`, prints the new hash
2. paste the printed hash into `npmDepsHash` in `lib/mkHarness.nix`
3. `nix flake check` — `checks.plugin-deps-are-current` must pass
