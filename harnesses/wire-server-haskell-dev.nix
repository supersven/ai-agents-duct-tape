{
  lib,
  pkgs,
  nixwrap,
  opencode,
  wireHoogleMcp,
  vanillaDev,
}:
let
  harnessLib = import ../lib {
    inherit
      lib
      pkgs
      nixwrap
      opencode
      ;
  };
  commonModules = vanillaDev.modules ++ [
    (import ./parts/hoogle-mcp.nix { inherit wireHoogleMcp; })
  ];
  # Anthropic and LLMaaS (Cloud Temple) model assignments are mutually
  # exclusive: only the default harness gets the Anthropic part.
  harness = harnessLib.mkHarness {
    name = "wire-server-haskell-dev";
    modules = commonModules ++ [
      (import ./parts/anthropic-models.nix {
        inherit lib;
        workspaceId = "wrkspc_01XqRi1aTpyhLJbNCYC3fuXz";
        agents = [
          "hoogle-search"
          "semble-search"
        ];
      })
    ];
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "wire-server-haskell-dev";
    modules = commonModules;
  };
in
{
  inherit (harness) package devShell;
  llmaas = {
    inherit (llmaasHarness) package devShell;
  };
}
