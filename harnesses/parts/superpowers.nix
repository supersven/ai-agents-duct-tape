{ pkgs, lib, agent-skills, superpowers }:
let
  agentLib = agent-skills.lib.agent-skills;
  sources = {
    superpowers = {
      path = superpowers;
      subdir = "skills";
    };
  };
  catalog = agentLib.discoverCatalog sources;
  allowlist = agentLib.allowlistFor {
    inherit catalog sources;
    enableAll = true;
  };
  selection = agentLib.selectSkills {
    inherit catalog sources allowlist;
  };
  bundle = agentLib.mkBundle {
    inherit pkgs;
    selection = selection;
  };
in
{
  config.skills = [ bundle ];
}
