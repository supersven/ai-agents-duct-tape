{ lib, pkgs, nixwrap, opencode }:
let
  generated = import ./types/generated.nix { inherit lib; };
  domain = import ./types/domain.nix { inherit lib generated; };
  modules = import ./modules.nix { inherit lib generated domain; };
  mkHarnessLib = import ./mkHarness.nix { inherit lib pkgs nixwrap opencode; evalHarness = modules.evalHarness; };
in
{
  inherit generated domain modules;
  inherit (mkHarnessLib) defaultWrapArgs;
  evalHarness = modules.evalHarness;
  mkHarness = mkHarnessLib.mkHarness;
}
