# Domain types: the scalar part-file types used by the harness module system.
# The harness part shape (config + skills/tools/agents/rules/commands/dependencies)
# is defined by evalHarness's base options in lib/modules.nix.
{ lib }:
{
  skill = lib.types.path;
  tool = lib.types.path;
  agent = lib.types.path;
  rule = lib.types.path;
  command = lib.types.path;
}
