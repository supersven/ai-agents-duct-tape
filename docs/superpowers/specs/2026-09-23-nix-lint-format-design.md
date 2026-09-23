# Nix Linting & Formatting Design

Date: 2026-09-23

## Goal

Give the flake's Nix code consistent formatting and linting, enforced in CI:

- `nix fmt` works from a bare invocation (no explicit file list).
- `nix flake check` fails when any committed Nix file is not formatted or
  contains dead code / statix-flagged anti-patterns.
- Machine-generated `lib/types/generated.nix` stays formatted without
  drifting from its generator or breaking the linters.

## Decisions

- **Formatter**: `nixfmt` (nixfmt-rfc-style, RFC 166 style; 1.5.0 from our
  nixpkgs — `pkgs.nixfmt`, not the deprecated `nixfmt-rfc-style` alias). The
  current tree was already nixfmt-adjacent, so adoption is a mechanical
  reformat.
- **Linters**: `deadnix` (dead code: unused lambda args, let bindings) and
  `statix` (anti-patterns: useless parens, `inherit` idioms, repeated attrset
  keys). Both run as **auto-fixers** (treefmt semantics): `deadnix --edit` and
  `statix fix`. `nix fmt` therefore formats *and* fixes dead code / lint
  findings, not just whitespace.
- **Runner**: [treefmt-nix](https://github.com/numtide/treefmt-nix), configured
  in `treefmt.nix` and evaluated per-system with
  `treefmt-nix.lib.evalModule pkgs ./treefmt.nix`. treefmt's git walk is
  `.gitignore`-aware, so `nix fmt` never touches `result`, `.worktrees/`, or
  `.direnv/`; the flake-source copy used by the check is already
  gitignore-filtered, so the two can't disagree.
- **Generated file**: `lib/types/generated.nix` is machine output. It stays
  nixfmt-formatted — `generate-types.py` pipes its output through `nixfmt`
  (required on PATH; the `update-types` app and `types-are-current` check both
  provide it) — but is excluded from deadnix/statix via
  `programs.{deadnix,statix}.excludes = [ "**/generated.nix" ]` (statix flags
  its hundreds of defensive parens; deadnix is silent but excluded for
  consistency).
- **Checks**: a single `checks.formatting = treefmtEval.config.build.check
  self`. The derivation copies `self`, `git init`s it, runs
  `treefmt --no-cache`, and fails on `git diff --exit-code`. It always runs
  cache-free, so CI cannot be fooled by a stale treefmt cache (which did bite
  during migration; see Evolution).
- **`apps.lint` dropped**: the earlier report-only `nix run .#lint` app was
  folded into `nix fmt` / `checks.formatting`.
- **Version coupling**: formatter/linter packages come from *our* nixpkgs
  (`programs.nixfmt.package` etc. default to `pkgs.*`), consistent with the
  `nixfmt` used by `generate-types.py`. A nixpkgs bump shipping a nixfmt whose
  output differs requires regenerating `generated.nix`; `types-are-current`
  guards this.

## Repo layout

```
treefmt.nix                      # treefmt-nix module: formatters, excludes
flake.nix                        # formatter + checks.formatting wiring
lib/types/generated.nix          # GENERATED, nixfmt-formatted (do not edit)
scripts/generate-types.py        # config.json -> generated.nix, piped through nixfmt
```

`treefmt.nix`:

```nix
_: {
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.deadnix.enable = true;
  programs.statix.enable = true;
  programs.deadnix.excludes = [ "**/generated.nix" ];
  programs.statix.excludes = [ "**/generated.nix" ];
}
```

(`_:` — the module needs no args; treefmt's auto-fixers rewrote the original
`{ pkgs, ... }:` on first run.)

## How it works

- **`nix fmt`** — the `formatter` output is `treefmtEval.config.build.wrapper`:
  a `treefmt` wrapper that finds the project root via
  `--tree-root-file=flake.nix` and runs with the generated config. The
  generated `treefmt.toml` declares three formatters over `*.nix`:

  | formatter | options | excludes |
  |---|---|---|
  | `nixfmt` | — | — |
  | `deadnix` | `--edit` | `**/generated.nix` |
  | `statix` | (fix wrapper) | `**/generated.nix` |

- **`checks.formatting`** — `treefmtEval.config.build.check self`: builds,
  copies `self` into a sandbox git repo (`git init` + `git add` + commit, git
  configured in `$HOME`), runs `treefmt --no-cache`, then `git diff
  --exit-code`. On failure it prints the offending diff. Requires no network.
- **`checks.types-are-current`** (unchanged mechanism, now with `nixfmt` in
  `nativeBuildInputs`) — regenerates `generated.nix` through
  `generate-types.py` + nixfmt and diffs against the committed file. Because
  the generator and treefmt share the same `nixfmt` binary, formatting and
  type-regeneration can never disagree.

## Evolution

Initially hand-rolled:

- a `nixfmt-tree` shell wrapper for `nix fmt` (bare `nix fmt` forwards no
  paths, so it walked `find . -name '*.nix'` with `xargs -0`);
- `checks.format` / `checks.lint` as `runCommand`s over a
  `lib.fileset.fileFilter` copy of the `.nix` files;
- a report-only `apps.lint` running `deadnix --fail` + `statix check`.

Replaced by treefmt-nix because the hand-rolled pieces duplicated treefmt's
job and diverged: the formatter's live-tree `find` and the checks' fileset
copy disagreed about `.git`/`.worktrees`/`result` handling, and statix forced
manual restructuring (`apps`/`checks` nesting) that treefmt would auto-apply.
treefmt-nix provides one canonical, gitignore-aware walker, a sandbox-safe
check builder, and the auto-fixer convention.

One migration gotcha: the first `nix fmt` left `treefmt.nix` in a
non-canonical state while the live treefmt **cache** recorded it as formatted,
so `nix fmt` reported "0 changed" while `checks.formatting` (which uses
`--no-cache`) wanted a reformat. Fixed with `nix fmt -- --no-cache`; the live
cache is keyed by file hash and self-corrects once content matches canonical
output. `checks.formatting` is unaffected by construction.

## Open questions (resolved)

- Auto-fix vs report-only linting: **auto-fix** (`nix fmt` also deletes dead
  code and applies statix rewrites). Upstream convention; tree is already
  clean, so no immediate rewrites. Worth remembering before running `nix fmt`
  on a WIP branch with dead code.
- Keep `apps.lint`: **dropped** — folded into `nix fmt` / `checks.formatting`.
- treefmt-nix input: pinned via the lock, `treefmt-nix.inputs.nixpkgs.follows
  = "nixpkgs"` to avoid a second (unused) nixpkgs in the lock.

## Verification

- `nix fmt` is idempotent (second run reports 0 changed).
- `nix flake check` passes: `checks.plugin-deps-are-current`,
  `checks.types-are-current`, `checks.superpowers`, `checks.formatting`.
- `checks.types-are-current` and `checks.formatting` both gate
  `generated.nix`; regeneration and formatting cannot diverge (same nixfmt
  binary).
- `nix run .#update-types` and `nix run .#update-node-modules` regenerate
  byte-identical files (`generated.nix`, `package-lock.json`), confirming the
  generator's nixfmt pipe and the reformatted heredocs are intact.