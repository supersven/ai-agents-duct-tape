{ lib, pkgs, nixwrap, opencode }:
let
  defaultWrapArgs =
    "-n -e COLORTERM -e ZELLIJ -e OPENCODE_CONFIG_DIR -e OPENCODE_CONFIG"
    + " -w ~/.config/opencode -w ~/.cache/opencode"
    + " -w ~/.local/share/opencode/ -w ~/.local/state/opencode/";
in
{
  inherit defaultWrapArgs;
  wrap = { wrapArgs ? defaultWrapArgs }:
    let
      hasConfig = lib.hasInfix "-e OPENCODE_CONFIG " wrapArgs;
      hasDir = lib.hasInfix "-e OPENCODE_CONFIG_DIR " wrapArgs;
      args = wrapArgs
        + lib.optionalString (!hasConfig) " -e OPENCODE_CONFIG"
        + lib.optionalString (!hasDir) " -e OPENCODE_CONFIG_DIR";
    in
    nixwrap.lib.${pkgs.system}.wrap {
      package = opencode;
      wrapArgs = args;
    };
}