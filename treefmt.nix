_: {
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.deadnix.enable = true;
  programs.statix.enable = true;
  # generated.nix is machine output; keep it nixfmt-formatted but out of the
  # linters (statix flags its defensive parens).
  programs.deadnix.excludes = [ "**/generated.nix" ];
  programs.statix.excludes = [ "**/generated.nix" ];
}
