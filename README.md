# ai-agents-tuct-tape

Nix flake providing pre-configured opencode harnesses for specialized usages.

## Updating node modules (plugin deps)

`node_modules` for custom tools is built by `buildNpmPackage` from
`lib/node-modules/package-lock.json`; the `package.json` version is derived
from the opencode input at eval time, so it cannot drift. When the opencode
input bumps:

1. `nix run .#update-node-modules` — regenerates `package-lock.json`, prints the new hash
2. paste the printed hash into `npmDepsHash` in `lib/mkHarness.nix`
3. `nix flake check` — `checks.plugin-deps-are-current` must pass
