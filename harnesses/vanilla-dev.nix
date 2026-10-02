{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
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
  modules = [
    (import ./parts/base.nix { inherit lib; })
    (import ./parts/superpowers.nix {
      inherit
        pkgs
        agent-skills
        superpowers
        ;
    })
    (import ./parts/semble.nix { inherit semble; })
    (import ./parts/be-concise.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "vanilla-dev";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "vanilla-dev";
    inherit modules;
  };
in
{
  inherit (harness) package devShell;
  llmaas = {
    inherit (llmaasHarness) package devShell;
  };
}
