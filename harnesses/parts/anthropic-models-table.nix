# Agent -> Anthropic model (+ reasoning variant) table, shared by
# `anthropic-models.nix` and the coverage flake check.
#
# Model IDs are pinned snapshots: Anthropic has no floating alias (`claude-
# sonnet-5` is the older Sonnet 5.0). Bump them here, in one place.
#
# Variants (opencode provider/transform.ts, read at tag v1.18.31):
#   opus/sonnet 5.x -> low medium high xhigh max (adaptive thinking + effort)
#   haiku 4.5       -> only high / max (budget thinking)
# Docs/code divergence (code wins, see AGENTS.md): opencode.ai/docs/models still
# lists only high/max for Anthropic, and opencode.ai/docs/agents never mentions
# the per-agent `variant` field; both exist in the code. With no variant,
# options() injects no thinking/effort, so Haiku runs without thinking.
# Haiku agents deliberately set no variant, i.e. run without thinking. An
# unknown variant is silently dropped by opencode, so names must be exact.
#
# Never set temperature/top_p/top_k: non-default values are a 400 on
# Sonnet 5.5 / Opus 5.5.
let
  opus = "anthropic/claude-opus-5-5";
  sonnet = "anthropic/claude-sonnet-5-5";
  haiku = "anthropic/claude-haiku-4-5";
in
{
  # Default model for everything that has no entry below.
  model = sonnet;
  # Lightweight tasks (opencode picks it itself; no variant support).
  small_model = haiku;

  # opencode's builtin agents. Always assigned.
  builtin = {
    # Long agentic coding; Anthropic: `medium` for well-specified tasks.
    build = {
      model = sonnet;
      variant = "medium";
    };
    # `opusplan` pattern: Opus plans, Sonnet executes. Plan output is small.
    plan = {
      model = opus;
      variant = "medium";
    };
    # Also receives superpowers' implementer and code-reviewer dispatches
    # ("general-purpose subagent"), hence `high`.
    general = {
      model = sonnet;
      variant = "high";
    };
    # Read-only, token-heavy fan-out; results are summarized for the parent.
    explore.model = haiku;
    title.model = haiku;
    summary.model = haiku;
    # Context continuity matters: not Haiku.
    compaction = {
      model = sonnet;
      variant = "medium";
    };
  };

  # Agents shipped as agents/<name>.md. Only emitted when the harness ships
  # them: an unknown name in `agent` makes opencode create a promptless
  # `mode: "all"` agent.
  shipped = {
    hoogle-search.model = haiku;
    semble-search.model = haiku;
    test-agent.model = haiku;
  };
}
