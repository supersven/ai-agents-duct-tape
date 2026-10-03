# Haskell API Search (Hoogle)

Use the `hoogle` MCP tool to look up Haskell library APIs — function names,
types, and documentation — instead of guessing or grepping. It covers what LSP
servers don't: functions in dependencies that the project doesn't use yet.

- The `query` is a Hoogle query, NOT a plain search. Bare text (`map`) searches
  names; `a -> a` searches types; `map :: (a -> b) -> [a] -> [b]` combines
  both; a leading `::` forces a type-only search.
- Scope results with bare filters (no `pkg`/`Module` keywords): `+packagename`
  restricts to a package (`map +base`), `-packagename` excludes one
  (`map -ghc-internal`), `+Module.Name` restricts to a module
  (`foldl' +Data.List`). Use them to cut internal-module noise
  (`ghc-internal`, `*.Internal`).
- Default instance is Wire Hoogle (all packages used by the target project).
  Set `general` to true ONLY when looking for a package not yet part of the
  project — this is rare.
- Results are structured JSON: package, module, signature (`item`), docs,
  `docs_truncated` (true when docs were cut to ~500 chars), `link`, the
  `source_link` of the real definition (best for re-exports), and `type`
  (function: null, module re-export: "module", package: "package").
- For multi-query research, dispatch the `hoogle-search` subagent; for a
  single lookup, call the `hoogle` tool directly.