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
`optparse-applicative`, `lrucache`, `text`, `bytestring`, `containers`,
`network-uri` (Source-href resolution), `tagsoup` (docs-page parsing).

Modules (small, single-purpose):

- `Wire.Hoogle.Types` — config record; hoogle result JSON types (`FromJSON`);
  two output shapes: `CachedEntry` (what the LRU stores: full untruncated
  docs, mangled link, resolved source link) and `OutputEntry` (what is served;
  `ToJSON`).
- `Wire.Hoogle.Query` — HTTP GET to `?mode=json&format=text&hoogle=<q>...`,
  parse via aeson.
- `Wire.Hoogle.Mangle` — URL mangling.
- `Wire.Hoogle.Source` — docs-page fetch + haddock "Source"-href extraction
  (below).
- `Wire.Hoogle.Cache` — `lrucache`-backed LRU wrapper around the parsed
  results, capacity from `HOOGLE_CACHE_MAX_ENTRIES`; plus the `SourceCache`
  (LRU keyed by docs-page URL).
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
**`CachedEntry`**s (full, untruncated `docs` plus the resolved `source_link`):
per request `cachedQuery` converts to **`OutputEntry`** via `toOutputEntry`,
truncating `docs` to ~500 chars unless `full_docs`. `full_docs` is therefore
**not** part of the cache key (server, query, count only) — a truncated and a
full-docs request for the same search share one cache entry and one HTTP fetch;
truncation is cheap, HTTP is not. Source links are resolved at fill time (they
need a docs-page fetch) and cached in the entry. Long docs are rare, so
caching full docs outweighs the larger per-entry footprint. Session-scoped;
results don't change during a session.

Two LRUs are composed into a single **`Caches`** record per session (created
together with the same capacity): `cachesHoogle` is the query cache above, and
`cachesSource` is the docs-page cache used only while filling the query cache
(see `source_link` below). The record is threaded through `cachedQuery` /
`toolCall` as one value, so call sites don't juggle two caches.

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
  (`map :: (a -> b) -> [a] -> [b]`), scope filters `+packagename` / `-packagename`
  (bare, e.g. `map +base`, `map -ghc-internal`), module filter `+Module.Name`
  (e.g. `foldl' +Data.List`), and a leading `::` for type-only search.
  Divergence from hoogle-haskell.org's wiki (which also accepts `+pkg`/`+Module`
  spellings): the Wire instance only honours the bare forms — `+pkg base`,
  `+Package base`, and `-pkg base` return empty / do not exclude. Verified live
  against both hoogle.zinfra.io and hoogle.haskell.org; the tool description,
  rule, and sub-agent all teach the bare forms.
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
`source_link` = the haddock "Source" link for the item, null if not derivable).
`type` is null for functions, `"module"` for module entries, `"package"` for
package entries. `also_in` lists every other `package/module` location that
re-exports the same definition.

Results are deduplicated by `source_link` (via `dedupeBySourceLink` in
`Wire.Hoogle.Types`, applied during the cache fill): Wire Hoogle returns the
same name once per re-exporting module (Prelude, Data.List, GHC.Base, ...), all
sharing the same resolved source link; only the first is kept, along with every
entry that has no source link. The collapsed rows' `package/module` locations
are merged into the survivor's `also_in` (deduped, in encounter order), so
re-export info is preserved, not lost. Verified live: `map` collapses to one
base row with `also_in = ["base/Data.List", "base/GHC.Base", "base/GHC.List"]`,
and `parseEither`'s aeson row lists `["yaml/Data.Yaml"]`. `count` is therefore
a maximum, not a guarantee. Note: dedup shrinks the served payload only, not
the fetch work — `resolveSourceLinks` resolves every row's docs page before
dedup runs, so a `map` query still fetches the Prelude/Data.List/GHC.Base pages
on the first (uncached) fill.

Divergence from the Wire docs pages: source hrefs are served as
`file//nix/...` (double slash) while the mangled docs link uses `file/nix/...`;
both resolve to the same content (verified 200 on both). `normalizeSourceLink`
(`Wire.Hoogle.Source`) collapses the repeated slash so cross-package re-exports
of the same definition compare equal by source link and can be deduplicated.

`source_link` follows the "Source" link Haddock renders next to the item's
anchor on the docs page — *not* URL munging. Munging is dead for re-exports:
e.g. base's `Control.Monad.forever` is defined in ghc-internal's
`GHC.Internal.Control.Monad`, so a munged `src/Control.Monad.html#forever` link
has no such anchor. Instead, `Wire.Hoogle.Source` fetches the docs page (the
mangled `link` minus fragment), extracts each def anchor's `class="link"`
"Source" href with tagsoup, resolves the relative href against the page URL
(network-uri), and caches the anchor→href map per page URL. Because this needs
a docs-page fetch, resolution happens at query time (part of the cache fill),
not per request; `CachedEntry` carries the resolved `ceSourceLink`. The page
cache is a second LRU (`SourceCache`) keyed by page URL, so repeated queries
over the same module refetch the page once. The extractor only attributes a
`class="link"` href to a def anchor that shares its container block: Haddock
renders a def and its Source link inside one `<p class="src">`, while
constructors live in `<td class="src">` table cells with no Source link of
their own — a stateful scan would otherwise attribute a later instance method's
Source link to the last constructor (`v:False` → `Bits Bool`'s `(.&.)`, seen
live on base's Prelude). Failed page fetches (HTTP error, no def anchors) are
not cached, so a transient failure is retried on the next query. A missing or
undecodable page, a def with no Source link (e.g. constructors), or an unknown
anchor yields null. Verified live: the resolved Source link for `forever`
points into ghc-internal's src page on both the Wire instance and hackage.

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