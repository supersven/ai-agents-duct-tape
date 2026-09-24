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
  harness = harnessLib.mkHarness {
    name = "vanilla-dev";
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
  };
in
{
  inherit (harness) package;
  devShell = pkgs.mkShell {
    packages = [ harness.package ];
  };
}
