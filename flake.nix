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

        checks.types-are-current = let
          configJson = pkgs.fetchurl {
            url = "https://opencode.ai/config.json";
            sha256 = "sha256-6MtuKHo4Uu40A/SAO+WtaxnblJSAN+qpZyElwzNCeSI=";
          };
        in
        pkgs.runCommand "types-are-current"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            python3 ${./scripts/generate-types.py} ${configJson} generated.nix
            diff -u ${./lib/types/generated.nix} generated.nix >&2
            echo ok > $out
          '';

        checks.superpowers = pkgs.runCommand "check-superpowers"
          {
            nativeBuildInputs = [ superpowersHarness.package ];
          }
          ''
            set -euo pipefail
            export HOME=$TMPDIR
            mkdir -p $HOME

            opencode debug config > config.json
            grep -q '"edit": "ask"' config.json
            grep -q '"bash": "ask"' config.json
            grep -q 'rules/team.md' config.json
            grep -q '"reviewer"' config.json
            grep -q '"status"' config.json

            opencode debug skill > skills.json
            grep -q 'local-demo' skills.json
            grep -q 'brainstorming' skills.json

            opencode debug agent plan > agent.json
            grep -q '"hello"' agent.json

            echo ok > $out
          '';
      }
    );
}
