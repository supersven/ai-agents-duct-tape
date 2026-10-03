# Wire Hoogle MCP + wire-server-haskell-dev harness

Date: 2026-10-02

## Goal

A Hoogle query MCP server, implemented as a Haskell cabal project, integrated
as a part of a new `wire-server-haskell-dev` harness. Hoogle covers the gap
that LSP servers leave open: knowledge about libraries and about functions not
yet used in the project.

## Background (verified facts that diverge from the feature request)

- The `hoogle` CLI's `search` command (with `--json`) only queries a **local
  `.hoo` database**; it has no `--server` flag for remote instances. The
  `hoogle --json "<query>"` format from the request cannot reach the Wire or
  general hoogle instances.
- Both hoogle.zinfra.io and hoogle.haskell.org expose their data via an HTTP
  JSON API only: `?mode=json&format=text&hoogle=<q>&start=<s>&count=<n>`.
  Neither exposes a downloadable database.
- Decision (user-approved): the MCP server queries these HTTP JSON APIs
  directly with `http-client`. No `hoogle` binary dependency.

## Runtime architecture

Cabal project at `mcps/wire-hoogle-mcp/`, one executable `wire-hoogle-mcp`.

Dependencies: `aeson`, `mcp-server`, `http-client`, `http-client-tls`,
`optparse-applicative`, `lrucache`, `text`, `bytestring`.

Modules (small, single-purpose):

- `Wire.Hoogle.Types` — config record; hoogle result JSON types (`FromJSON`);
  two output shapes: `CachedEntry` (what the LRU stores: full untruncated
  docs, mangled link) and `OutputEntry` (what is served; `ToJSON`).
- `Wire.Hoogle.Query` — HTTP GET to `?mode=json&format=text&hoogle=<q>...`,
  parse via aeson.
- `Wire.Hoogle.Mangle` — URL mangling and source-link derivation (below).
- `Wire.Hoogle.Cache` — `lrucache`-backed LRU wrapper around the parsed
  results, capacity from `HOOGLE_CACHE_MAX_ENTRIES`.
- `Wire.Hoogle.CLI` — `optparse-applicative` parser (below).
- `Main.hs` — `McpServerInfo` + handlers, `runMcpServerStdio`.

Uses mcp-server's **manual** `ToolListHandler`/`ToolCallHandler` (not TH
derivation) for full control of tool descriptions and input schema. `Content`
has only `ContentText`, so the tool result is the parsed-and-rebuilt JSON
rendered as a text block.

### Config

Env vars with baked-in defaults, read at startup:

- `WIRE_HOOGLE_URL` (default `https://hoogle.zinfra.io`)
- `GENERAL_HOOGLE_URL` (default `https://hoogle.haskell.org`)
- `HOOGLE_CACHE_MAX_ENTRIES` (default `5000`, see Cache below)

### Path mangling

The Wire instance returns `file:///nix/store/<hash>-<pkg>-<ver>-doc/...`
doc URLs (useless to an agent). Verified that hoogle.zinfra.io serves those
docs under `https://hoogle.zinfra.io/file/nix/store/<hash>-...`.

Mangling rule: for Wire-instance results, rewrite each `url`/`module.url`/
`package.url` that starts with `file://` by replacing the `file://` prefix
with `<wireOrigin>/file`, keeping any `#fragment`. General-instance (hackage)
URLs pass through untouched.

### Cache

In-memory LRU via the `lrucache` library (`Data.Cache.LRU.IO`, mutable IO
wrapper) — no custom cache implementation. True LRU: on hit, refresh recency;
on insert, evict the least-recently-used entries when at capacity.

Capacity is entry-count based (the library caps by count, not bytes);
configurable via `HOOGLE_CACHE_MAX_ENTRIES`. Default 5000. The cache stores
**`CachedEntry`**s (full, untruncated `docs`): per request `cachedQuery`
converts to **`OutputEntry`** via `toOutputEntry`, truncating `docs` to ~500
chars unless `full_docs` and deriving the `source_link`. `full_docs` is
therefore **not** part of the cache key (server, query, count only) — a
truncated and a full-docs request for the same search share one cache entry
and one HTTP fetch; truncation/derivation is cheap, HTTP is not. Long docs
are rare, so caching full docs outweighs the larger per-entry footprint.
Session-scoped; results don't change during a session.

### CLI

`optparse-applicative`, one executable with two modes:

- **default (no args)** — run the MCP stdio server. Keeps the harness MCP
  command as `[ "${wireHoogleMcp}/bin/wire-hoogle-mcp" ]`.
- **`query <hoogle-query>`** — print the same mangled JSON results to stdout
  for manual testing. Options: `--general` (general instance), `--count N`
  (default 10), `--full-docs` (no truncation). Mirrors the MCP tool's args.
  Reads the same env defaults (instance URLs overridable via
  `WIRE_HOOGLE_URL`/`GENERAL_HOOGLE_URL`); shares the LRU cache.

`optparse-applicative`'s standard `--help` (via `helper`) documents every
command, option, and default on both modes.

## Tools

One MCP tool, `hoogle` (manual handler; descriptions/schema crafted for AI
agents):

- `query` (required, string) — a Hoogle query, *not* a plain search. The
  description teaches the syntax: bare text (`map`), type signatures
  (`a -> a`, `Text -> IO ()`), combined text + type
  (`map :: (a -> b) -> [a] -> [b]`), scope filters `+pkg` / `-pkg`, module
  filter `+Module`, and `::` for type-only search.
- `general` (optional, boolean, default false) — search the general hoogle
  instance (hoogle.haskell.org) for a package not yet in the target project;
  rare.
- `count` (optional, integer, default 10) — max results, clamped to 1..50 (both
  the tool call and the CLI).
- `full_docs` (optional, boolean, default false) — return full `docs` instead
  of the ~500-char truncation.

Output: compact JSON array; each element `{package, module, item, docs,
docs_truncated, link, source_link}` (`docs_truncated` is true when `docs` was
truncated to ~500 chars; `link` = mangled docs URL, null if absent;
`source_link` = derived haddock source page, null if not derivable).

`source_link` is derived from `link` per request (not cached): insert `src/`
before the page, convert `-` back to `.` in the module name, and drop the
`#v:`/`#t:` anchor prefix — e.g. `.../html/Data-Aeson-KeyMap.html#v:map` →
`.../html/src/Data.Aeson.KeyMap.html#map`. Non-module pages (`index.html`,
`doc-index.html`, ...) yield null. Verified live: the derived URLs resolve on
both the Wire instance (200) and hackage (redirects to the current package
version, as the docs links themselves do).

`McpServerInfo.serverInstructions` gives a 2-3 sentence overview of the tool
and the query-not-search distinction.

## Rule and sub-agent (not a skill)

A `rules/hoogle.md` rule (like `rules/semble.md`): when to use the MCP tool,
wire instance by default, `general` only for packages not yet in the project,
plus a hoogle-query syntax reminder. No skill — the tool description and
server instructions already explain the query syntax; a skill would duplicate
them. Revisit only if agents misuse the tool.

A dedicated sub-agent `agents/hoogle-search.md` (like `agents/semble-search.md`):
`mode: subagent`, minimal permissions (read only, no bash), system prompt that
uses the `hoogle` MCP tool with the wire-first / general-only-rare policy and a
query workflow. It is dispatched by the main agent's model when a fitting
question appears (driven by its `description` + the rule, not an engine-level
auto-trigger — same mechanism as `semble-search`). Keeps multi-query research
out of the main agent's context; in `llmaas` variants it can pin a small/cheap
model.

## Nix integration

- `wireHoogleMcp = pkgs.haskellPackages.callCabal2nix "wire-hoogle-mcp"
  ./mcps/wire-hoogle-mcp {}` in flake.nix. No committed cabal2nix.nix, no
  update app (IFD verified to work under `nix flake check`). `mcp-server`,
  `http-client`, `http-client-tls` are all present in nixpkgs `haskellPackages`.
- Not jailed (we own and trust it; the opencode jail's network covers it).
- Part `harnesses/parts/hoogle-mcp.nix` (matches sembl.e pattern):

  ```nix
  { wireHoogleMcp }:
  {
    config.opencode.mcp["wire-hoogle"] = {
      type = "local";
      command = [ "${wireHoogleMcp}/bin/wire-hoogle-mcp" ];
      environment = {
        WIRE_HOOGLE_URL = "https://hoogle.zinfra.io";
        GENERAL_HOOGLE_URL = "https://hoogle.haskell.org";
      };
    };
    config.rules = [ ./../../rules/hoogle.md ];
    config.agents = [ ./../../agents/hoogle-search.md ];
    config.dependencies = [ wireHoogleMcp ];
  }
  ```

- Harness `harnesses/wire-server-haskell-dev.nix`: composes `base` +
  `superpowers` + `be-concise` + `hoogle-mcp`; provides `package`, `devShell`,
  and an `llmaas` variant (matches every existing harness).
- flake.nix wiring: `packages`/`devShells` for `wire-server-haskell-dev` and
  `wire-server-haskell-dev-llmaas`; `checks.wire-server-haskell-dev`
  (bwrap sandbox → `opencode debug config`, jq assertions on
  `.mcp["wire-hoogle"]`, rule instruction present, `.agent has("hoogle-search")`,
  `debug skill` presence) following the vanilla-dev check pattern.

## Verification

`git add -A && nix flake check` (all checks incl. `checks.formatting` must
pass). Manual: `nix run .#wire-server-haskell-dev` then query the `hoogle`
tool; `nix run` the MCP package's `query` subcommand directly.