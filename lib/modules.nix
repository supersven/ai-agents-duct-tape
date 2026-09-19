{ lib, generated, domain }:
{
  evalHarness = { modules }:
    let
      base = {
        options = {
          opencode = lib.mkOption {
            type = lib.types.submodule { options = generated.options.Config; };
            description = "opencode configuration fragment";
          };
          skills = lib.mkOption { type = lib.types.listOf domain.skill; default = [ ]; };
          tools = lib.mkOption { type = lib.types.listOf domain.tool; default = [ ]; };
          agents = lib.mkOption { type = lib.types.listOf domain.agent; default = [ ]; };
          rules = lib.mkOption { type = lib.types.listOf domain.rule; default = [ ]; };
          commands = lib.mkOption { type = lib.types.listOf domain.command; default = [ ]; };
          dependencies = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
        };
      };
      res = lib.evalModules {
        modules = [ base ] ++ modules;
      };
    in
    {
      config = res.config.opencode;
      skills = res.config.skills;
      tools = res.config.tools;
      agents = res.config.agents;
      rules = res.config.rules;
      commands = res.config.commands;
      dependencies = res.config.dependencies;
    };
}