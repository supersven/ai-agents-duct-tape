{ pkgs }:
{
  config.opencode.lsp = true;
  # Servers not tied to a language toolchain. HLS is deliberately absent: it
  # must match the GHC of the outer env, so it is picked up from there.
  config.dependencies = [
    pkgs.nixd
    pkgs.bash-language-server
    pkgs.yaml-language-server
  ];
}
