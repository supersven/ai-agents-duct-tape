{
  lib,
  # Names of agents/<name>.md the harness ships (keys of `shipped` in the
  # table). Builtin agents are always assigned.
  agents ? [ ],
}:
let
  table = import ./anthropic-models-table.nix;
  unknown = builtins.filter (a: !(table.shipped ? ${a})) agents;
in
assert lib.assertMsg (unknown == [ ])
  "anthropic-models: no model assignment for agent(s) ${lib.concatStringsSep ", " unknown}; add to anthropic-models-table.nix";
{
  config.opencode = {
    inherit (table) model small_model;
    agent = table.builtin // lib.getAttrs agents table.shipped;
  };
}
