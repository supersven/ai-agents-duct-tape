Nix flake to provide pre-configured ai agents (harnesses) for specialized
usages (e.g. languages, projects, tasks).

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

Whenever an object can also be declared as file (e.g tool, skill, sub-agent),
such a file file be declared in a dedicated folder (`./tools/<tool-name>`,
`./skills/<skill-name>`, `./agents/<agent-name>`).

Whenever it can also be declared in the opencode config, it should also be
possible in Nix.

Skills are a special case, because they can also be pulled from remote. That's
why we're using agent-skills-nix.

Configuration happens by composing parts and the opencode agent nix modules to config
files for the agent. The agent and these harness files are bundled to a derivation.
In this derivation, environment variables point the agent to its harness files.

Each harness derivation is made available via a dedicated devShell and output
(to be permanently installable).

These derivations also have dependencies like e.g. LSP servers or linters.
Each part should be self-sufficient: E.g. if a tool needs some dependencie, its
module should provide it.
