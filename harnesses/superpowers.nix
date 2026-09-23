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
  harness = harnessLib.mkHarness {
    name = "superpowers";
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
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
}
