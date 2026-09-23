# ai-agents-tuct-tape

Nix flake providing pre-configured opencode harnesses for specialized usages.

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
