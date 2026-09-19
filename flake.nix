{
  description = "Pre-configured ai agent harnesses for specialized usages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    llm-agents.url = "github:numtide/llm-agents.nix";
    nixwrap.url = "github:rti/nixwrap";
    agent-skills.url = "github:Kyure-A/agent-skills-nix";
    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      llm-agents,
      nixwrap,
      agent-skills,
      superpowers,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        opencode = llm-agents.packages.${system}.opencode;
        harnessLib = import ./lib {
          inherit lib pkgs nixwrap opencode;
        };
        superpowersHarness = import ./harnesses/superpowers.nix {
          inherit lib pkgs nixwrap opencode agent-skills superpowers;
        };
      in
      {
        packages.default = harnessLib.wrap { };
        packages.superpowers = superpowersHarness.package;

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.default ];
        };
        devShells.superpowers = superpowersHarness.devShell;

        apps.update-types = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "update-types" ''
            export PATH=${lib.makeBinPath [ pkgs.curl pkgs.python3 ]}:$PATH
            exec ${./scripts/update-types.sh}
          ''}/bin/update-types";
        };

        checks.types-are-current = pkgs.runCommand "types-are-current"
          {
            nativeBuildInputs = [ pkgs.curl pkgs.python3 ];
          }
          ''
            tmp=$(mktemp -d)
            curl -fsSL https://opencode.ai/config.json -o "$tmp/config.json"
            python3 ${./scripts/generate-types.py} "$tmp/config.json" "$tmp/generated.nix"
            diff -u ${./lib/types/generated.nix} "$tmp/generated.nix" >&2
            echo ok > $out
          '';
      }
    );
}
