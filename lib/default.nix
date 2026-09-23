{
  lib,
  pkgs,
  nixwrap,
  opencode,
}:
let
  generated = import ./types/generated.nix { inherit lib; };
  domain = import ./types/domain.nix { inherit lib; };
  modules = import ./modules.nix { inherit lib generated domain; };
  mkHarnessLib = import ./mkHarness.nix {
    inherit
      lib
      pkgs
      nixwrap
      opencode
      ;
    inherit (modules) evalHarness;
  };
in
{
  inherit generated domain modules;
  inherit (mkHarnessLib) defaultWrapArgs;
  inherit (modules) evalHarness;
  inherit (mkHarnessLib) mkHarness;
}
