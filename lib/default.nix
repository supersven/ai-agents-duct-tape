{ lib, pkgs, nixwrap, opencode }:
let
  generated = import ./types/generated.nix { inherit lib; };
  domain = import ./types/domain.nix { inherit lib generated; };
  modules = import ./modules.nix { inherit lib generated domain; };
  wrapLib = import ./wrap.nix { inherit lib pkgs nixwrap opencode; };
  mkHarnessLib = import ./mkHarness.nix {
    inherit lib pkgs;
    evalHarness = modules.evalHarness;
    wrap = wrapLib.wrap;
    inherit (wrapLib) defaultWrapArgs;
  };
in
{
  inherit generated domain modules;
  inherit (wrapLib) defaultWrapArgs;
  evalHarness = modules.evalHarness;
  wrap = wrapLib.wrap;
  mkHarness = mkHarnessLib.mkHarness;
}