{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
  wireHoogleMcp,
  semble,
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
  commonModules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/hoogle-mcp.nix { inherit wireHoogleMcp; })
    (import ./parts/semble.nix { inherit semble; })
    (import ./parts/be-concise.nix)
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
