{
  lib,
  pkgs,
  nixwrap,
  opencode,
  agent-skills,
  superpowers,
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
    (import ./parts/test-skill.nix)
    (import ./parts/test-tool.nix)
    (import ./parts/test-agent.nix)
    (import ./parts/test-command.nix)
    (import ./parts/test-rule.nix)
  ];
  harness = harnessLib.mkHarness {
    name = "superpowers";
    inherit modules;
  };
  llmaasHarness = harnessLib.enrichWithLLMaaS {
    name = "superpowers";
    inherit modules;
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
  llmaas = {
    inherit (llmaasHarness) package;
    devShell = pkgs.mkShell {
      packages = [ llmaasHarness.package ];
    };
  };
}
