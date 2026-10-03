# Haskell API Search (Hoogle)

Use the `hoogle` MCP tool to look up Haskell library APIs — function names,
types, and documentation — instead of guessing or grepping. It covers what LSP
servers don't: functions in dependencies that the project doesn't use yet.

- The `query` is a Hoogle query, NOT a plain search. Bare text (`map`) searches
  names; `a -> a` searches types; `map :: (a -> b) -> [a] -> [b]` combines
  both; `+pkg` / `-pkg` restrict packages; `+Module` restricts modules.
- Default instance is Wire Hoogle (all packages used by the target project).
- Set `general` to true ONLY when looking for a package not yet part of the
  project — this is rare.
- Results are structured JSON: package, module, signature (`item`), docs, a
  docs link, and `type` (the hoogle result kind, e.g. `module` for module
  re-exports; `null` otherwise).