{ semble, }: {
  config.opencode.mcp.semble = {
    type = "local";
    # semble (no subcommand) auto-dispatches to the MCP server, matching
    # upstream's opencode docs (`uvx --from "semble[mcp]" semble`). `semble` is
    # the nixwrap-jailed derivation passed in; the [mcp] extra is built in.
    command = [ "${semble}/bin/semble" ];
  };
  config.rules = [ ./../../rules/semble.md ];
  # agents/semble-search.md is a copy of upstream src/semble/agents/opencode.md
  # with the "If semble is not on $PATH, use uvx --from semble[mcp] semble"
  # fallback dropped: this harness always puts the semble CLI on PATH via
  # `dependencies`, so uvx would be dead weight. Keep the rest in sync with
  # upstream when it changes.
  config.agents = [ ./../../agents/semble-search.md ];
  config.dependencies = [ semble ];
}
