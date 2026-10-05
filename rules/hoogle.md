# Haskell API Search (Hoogle)

Look up Haskell library APIs — function names, types, packages, docs — with
Hoogle instead of guessing, grepping, or fetching docs by hand. It covers what
LSP servers don't: functions in dependencies the project doesn't use yet.

- Always dispatch the `hoogle-search` subagent for any hoogle/API lookup;
  never call the `hoogle` tool directly (even a single lookup must be
  delegated).
- Brief it with the exact question, known package/module/type, and the answer
  you need (signature, docs, examples). For follow-ups on the same question,
  resume its session with `task_id`.
- API questions go to `hoogle-search`; local codebase questions go to
  `explore`.
- If Hoogle lacks coverage (package not on Hackage, internal/proprietary code,
  missing docs), fallback is fine: webfetch/websearch, grep, or reading
  vendored sources (primary/explore own those followups).
