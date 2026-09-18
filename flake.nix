{
  description = "Pre-configured ai agent harnesses for specialized usages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixwrap.url = "github:rti/nixwrap";
    agent-skills.url = "github:Kyure-A/agent-skills-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      llm-agents,
      nixwrap,
      agent-skills,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        wrap = nixwrap.lib.${system}.wrap;
        opencode = llm-agents.packages.${system}.opencode;
      in
      {
        packages.default = wrap {
          package = opencode;
        };

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.default ];
        };
      }
    );
}