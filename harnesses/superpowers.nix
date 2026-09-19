{ lib, pkgs, nixwrap, opencode, agent-skills, superpowers }:
let
  harnessLib = import ../lib {
    inherit lib pkgs nixwrap opencode;
  };
  harness = harnessLib.mkHarness {
    name = "superpowers";
    modules = [
      (import ./parts/base.nix { inherit lib; })
      (import ./parts/superpowers.nix { inherit pkgs lib agent-skills superpowers; })
      (import ./parts/skill.nix)
      (import ./parts/tool.nix)
      (import ./parts/agent.nix)
      (import ./parts/command.nix)
      (import ./parts/rule.nix)
    ];
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
}