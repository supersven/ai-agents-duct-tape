Nix flake to provide pre-configured ai agents (harnesses) for specialized
usages (e.g. by languages, projects, tasks).

Opencode is the only agent to target.

The agents are taken from
[llm-agents.nix](https://github.com/numtide/llm-agents.nix) and are jailed with
[nixwrap](https://github.com/rti/nixwrap).

Skills are fetched with
[agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix). Skills can
have local paths (`./skills/<skill-name>`) or remote URLs.

The configuration schema of opencode is defined by
https://opencode.ai/config.json and explained in
https://opencode.ai/docs/en/config/ . It is reflected by the nix configuration
to make it intuitive.

To keep them easier in sync, the types derived from
https://opencode.ai/config.json are kept separately from the modules'
project-specific ones (domain types). The domain types use the derived ones,
though.

Whenever an object can also be declared as file (e.g tool, skill, sub-agent),
such a file file be declared in a dedicated folder (`./tools/<tool-name>`,
`./skills/<skill-name>`, `./agents/<agent-name>`).

Whenever it can also be declared in the opencode config, it should also be
possible in Nix.

Skills are a special case, because they can also be pulled from remote. That's
why we're using agent-skills-nix.

Each harness part is a Nix module. Harness part modules are typed.
A harness part module does not necessarily have input options, but can.

The output type is like:

```
{
  config :: <opencode config type>;
  skills :: [<skill file or directory to be copied>],
  tools :: [<tool file to be copied>],
  rules :: [<rule file to be copied>],
  commands :: [<command file to be copied>],
}
```

Configuration happens by composing (merging) harness part modules configs
and copying parts files for the agent. The agent and these harness files are
bundled to a derivation. In this derivation, environment variables point the
agent to its harness files.

Each harness derivation is made available via a dedicated devShell and output
(to be permanently installable).

The structure of the derivation regarding files must adhere to opencode's
expectations to find these and interpret them correctly.

These derivations also have dependencies like e.g. LSP servers or linters.
Each part should be self-sufficient: E.g. if a tool needs some dependencie, its
module should provide it.
