Provide basic LSP functionality as MCP and CLI tool.

The program should be named `dtg` (as in duct tape grep).

Handle as much as possible with `ast-grep` (or `ripgrep` if the required
functionality isn't provided `ast-grep`), then start a GHC session to refine
the result. I.e. because `ast-grep` cannot match on precise types and
provenances, it can only provide lists of candidate matches, which need to be
validated / filtered / refined.

The GHC session should use the least amount of compilation stages as possible.
Depending on the task, up to the renamer or type-checker stage.

Bundle queries up-front such that multiple can use the same session.
E.g. if there are two candidates in the same Module, one session can be used to
validate both. If this also works cross-module is an open question and can be
figured out during development. (Sessions are expensive and are getting more
expensive with bigger scopes; thus there needs to be a balance between session
reuse and session weight due to amount of loaded modules. Make some experiments
to find the sweet spot!)

Ideally, handle as much as possible with `ast-grep` calls and only dive into
GHC API / sessions to refine results. All result MUST BE PRECISE AND CORRECT
(no false positives!)!!!

Use hie-bios and implicit-hie packages to find the session's parameters. Add
parameters like `-O0` to speed up the process. Investigate the usefulness of
parallelism; e.g. `-jsem`. The maximal parallelism should be capped to the
amount of CPU cores.
GHC sessions can be started in parallel to improve performance. In this case,
divide the amount of cores by the amount of sessions (equal distribution).

Communication with `ast-grep` should be in JSON. Run the tool as command, then
parse the JSON results. `ast-grep` is documented here:
https://ast-grep.github.io/llms-full.txt

The MCP / CLI tool should provide these tools:

- find_references
- find_definition
- hover_info
  - type and haddock (if any)
- call_graph
- reference_graph
- module-exports
- global_symbol_search
- type_of
- type_at_point

Check if all these can be implemented and - in case - propose removals or additions.
Checking here means a deep research, mapping desired tools to `ast-grep` and
GHC API calls.

For implementation, use a tracer bullet strategy: Implement each feature
one-by-one, end-to-end.

The tool should be stateless (no HIE file directory, database, or similar).
It's fine to have temporary files as by-product of the GHC session creation
process. But, we should not rely on them in subsequent runs.

Target GHC is GHC 9.10 for now.

Integration testing should happen against a multi-module, multi-component Cabal
project. Take this as test fixture. Create more fixtures on demand / need. In
integration tests, it's fine to call the outer-boundary Haskell functions
directly (and not going via tool execution).

The tool should be a combined binary representing both: MCP and CLI tool. I.e.
calling the CLI tool with `<toolname> mcp` starts the MCP server. Other
commands (listed tools) are interpreted as CLI tool invocations.

Keep in mind, that components may have conflicting modules / functions as long
as they aren't imported together. This should also be covered by integration
tests and their fixtures. Investigate how this can be covered by the GHC API.
