{ lib, pkgs, nixwrap, opencode }:
let
  defaultWrapArgs =
    "-n -e COLORTERM -e ZELLIJ -e OPENCODE_CONFIG_DIR -e OPENCODE_CONFIG"
    + " -w ~/.config/opencode -w ~/.cache/opencode"
    + " -w ~/.local/share/opencode/ -w ~/.local/state/opencode/";
  # nixwrap's raw wrap.sh has a `#!/usr/bin/env bash` shebang (no /usr in a
  # nix build sandbox) and binds network files with `--ro-bind` (fails when
  # /etc/resolv.conf etc. are absent, as in a sandbox). Build a patched copy.
  wrapSh = pkgs.runCommand "wrap.sh" { } ''
    sed -e '1c#!${pkgs.bash}/bin/bash' \
        -e 's|--ro-bind /etc/resolv.conf|--ro-bind-try /etc/resolv.conf|' \
        -e 's|--ro-bind /etc/ssl /etc/ssl|--ro-bind-try /etc/ssl /etc/ssl|' \
        -e 's|--ro-bind /etc/static/ssl /etc/static/ssl|--ro-bind-try /etc/static/ssl /etc/static/ssl|' \
        ${nixwrap.outPath}/wrap.sh > $out
    chmod +x $out
  '';
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
    pkgs.symlinkJoin {
      name = opencode.name;
      paths = [ opencode ];
      postBuild = ''
        mv $out/bin/opencode{,-nowrap}
        cat > $out/bin/opencode <<EOF
          export PATH=${pkgs.bubblewrap}/bin:\$PATH
          exec ${wrapSh} ${args} ${opencode}/bin/opencode "\$@"
        EOF
        chmod a+x $out/bin/opencode
      '';
    };
}