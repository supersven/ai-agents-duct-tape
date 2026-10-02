{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
  wireHoogleMcp,
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
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/hoogle-mcp.nix { inherit wireHoogleMcp; })
    (import ./parts/be-concise.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "wire-server-haskell-dev";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "wire-server-haskell-dev";
    inherit modules;
  };
in
{
  inherit (harness) package devShell;
  llmaas = {
    inherit (llmaasHarness) package devShell;
  };
}
