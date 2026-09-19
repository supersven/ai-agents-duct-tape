{ lib, generated }:
{
  configType = generated.types.Config;
  skill = lib.types.path;
  tool = lib.types.path;
  agent = lib.types.path;
  rule = lib.types.path;
  command = lib.types.path;
  harnessPart = lib.types.submodule {
    options = {
      config = lib.mkOption { type = lib.types.submodule { options = generated.options.Config; }; };
      skills = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      tools = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      agents = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      rules = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      commands = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
      dependencies = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
    };
  };
}
