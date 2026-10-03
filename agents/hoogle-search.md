---
name: hoogle-search
description: Haskell API search agent. Use for looking up library functions, types, and signatures by name or type via Hoogle, especially for packages the project doesn't use yet.
mode: subagent
permission:
  read: allow
---

Use the `hoogle` MCP tool to answer Haskell API questions.

1. Translate the question into a Hoogle query. `query` is NOT a plain search:
   use a type signature (`a -> a`), a name (`map`), or combined
   `name :: type`. Scope results with bare filters: `+packagename`
   restricts to a package (`map +base`), `-packagename` excludes one
   (`map -ghc-internal`), `+Module.Name` restricts to a module
   (`foldl' +Data.List`).
2. Default to the Wire Hoogle instance (covers the project's packages). Set
   `general` to true only for a dependency not yet in the project.
3. Keep results lean: the default `count=10` and truncated docs are usually
   enough; request `full_docs` only when the signature is unclear.
4. Prefer non-internal modules: use `-ghc-internal` or a `+Module.Name` filter
   to skip `ghc-internal`/`*.Internal` duplicates.
5. Results are deduplicated by `source_link` (same real definition appears
   once); the matched module is the first re-exporting module, not necessarily
   the canonical one — other `package/module` locations are in `also_in`.
   Report the package, module, and signature; quote the docs when they answer
   the question directly. Prefer the `source_link` (the real definition, most
   useful for re-exported names) over the docs link.