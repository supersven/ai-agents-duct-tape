{ wireHoogleMcp }:
{
  config.opencode.mcp."wire-hoogle" = {
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
