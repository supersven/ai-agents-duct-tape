{ lib }:
let
  mkOption = lib.mkOption;
  options = {
    Config = {
      "$schema" = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "JSON schema reference for configuration validation";
      };
      shell = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "Default shell to use for terminal and bash tool";
      };
      logLevel = mkOption {
        type = lib.types.nullOr (generatedTypes.LogLevel);
        default = null;
        description = "Log level";
      };
      server = mkOption {
        type = lib.types.nullOr (generatedTypes.ServerConfig);
        default = null;
        description = "Server configuration for opencode serve and web commands";
      };
      command = mkOption {
        type = lib.types.nullOr (
          lib.types.attrsOf (
            lib.types.submodule {
              options = {
                template = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                description = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                agent = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                model = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                variant = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                subtask = mkOption {
                  type = lib.types.nullOr (lib.types.bool);
                  default = null;
                };
              };
            }
          )
        );
        default = null;
        description = "Command configuration, see https://opencode.ai/docs/commands";
      };
      skills = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              paths = mkOption {
                type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                default = null;
                description = "Additional paths to skill folders";
              };
              urls = mkOption {
                type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                default = null;
                description = "URLs to fetch skills from (e.g., https://example.com/.well-known/skills/)";
              };
            };
          }
        );
        default = null;
        description = "Additional skill folder paths";
      };
      references = mkOption {
        type = lib.types.nullOr (
          lib.types.attrsOf (
            lib.types.oneOf [
              (lib.types.str)
              (generatedTypes."ConfigV2.Reference.Git")
              (generatedTypes."ConfigV2.Reference.Local")
            ]
          )
        );
        default = null;
        description = "Named git or local directory references";
      };
      reference = mkOption {
        type = lib.types.nullOr (
          lib.types.attrsOf (
            lib.types.oneOf [
              (lib.types.str)
              (generatedTypes."ConfigV2.Reference.Git")
              (generatedTypes."ConfigV2.Reference.Local")
            ]
          )
        );
        default = null;
        description = "@deprecated Use 'references' field instead. Named git or local directory references";
      };
      watcher = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              ignore = mkOption {
                type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                default = null;
              };
            };
          }
        );
        default = null;
      };
      snapshot = mkOption {
        type = lib.types.nullOr (lib.types.bool);
        default = null;
        description = "Enable or disable snapshot tracking. When false, filesystem snapshots are not recorded and undoing or reverting will not undo/redo file changes. Defaults to true.";
      };
      plugin = mkOption {
        type = lib.types.nullOr (
          lib.types.listOf (
            lib.types.oneOf [
              (lib.types.str)
              (lib.types.listOf (
                lib.types.oneOf [
                  (lib.types.str)
                  (lib.types.attrs)
                ]
              ))
            ]
          )
        );
        default = null;
      };
      share = mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "manual"
            "auto"
            "disabled"
          ]
        );
        default = null;
        description = "Control sharing behavior:'manual' allows manual sharing via commands, 'auto' enables automatic sharing, 'disabled' disables all sharing";
      };
      autoshare = mkOption {
        type = lib.types.nullOr (lib.types.bool);
        default = null;
        description = "@deprecated Use 'share' field instead. Share newly created sessions automatically";
      };
      autoupdate = mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            (lib.types.bool)
            (lib.types.enum [ "notify" ])
          ]
        );
        default = null;
        description = "Automatically update to the latest version. Set to true to auto-update, false to disable, or 'notify' to show update notifications";
      };
      disabled_providers = mkOption {
        type = lib.types.nullOr (lib.types.listOf (lib.types.str));
        default = null;
        description = "Disable providers that are loaded automatically";
      };
      enabled_providers = mkOption {
        type = lib.types.nullOr (lib.types.listOf (lib.types.str));
        default = null;
        description = "When set, ONLY these providers will be enabled. All other providers will be ignored";
      };
      model = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "Model to use in the format of provider/model, eg anthropic/claude-2";
      };
      small_model = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "Small model to use for tasks like title generation in the format of provider/model";
      };
      default_agent = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "Default agent to use when none is specified. Must be a primary agent. Falls back to 'build' if not set or if the specified agent is invalid.";
      };
      subagent_depth = mkOption {
        type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x >= 0 && x <= 9007199254740991)));
        default = null;
        description = "Maximum subagent nesting depth. Defaults to 1, which prevents subagents from launching subagents.";
      };
      username = mkOption {
        type = lib.types.nullOr (lib.types.str);
        default = null;
        description = "Custom username to display in conversations instead of system username";
      };
      mode = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              build = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              plan = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
            };
            freeformType = lib.types.attrsOf (generatedTypes.AgentConfig);
          }
        );
        default = null;
        description = "@deprecated Use `agent` field instead.";
      };
      agent = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              plan = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              build = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              general = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              explore = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              title = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              summary = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
              compaction = mkOption {
                type = lib.types.nullOr (generatedTypes.AgentConfig);
                default = null;
              };
            };
            freeformType = lib.types.attrsOf (generatedTypes.AgentConfig);
          }
        );
        default = null;
        description = "Agent configuration, see https://opencode.ai/docs/agents";
      };
      provider = mkOption {
        type = lib.types.nullOr (lib.types.attrsOf (generatedTypes.ProviderConfig));
        default = null;
        description = "Custom provider configurations and model overrides";
      };
      mcp = mkOption {
        type = lib.types.nullOr (
          lib.types.attrsOf (
            lib.types.oneOf [
              (lib.types.oneOf [
                (generatedTypes.McpLocalConfig)
                (generatedTypes.McpRemoteConfig)
              ])
              (lib.types.submodule {
                options = {
                  enabled = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                };
              })
            ]
          )
        );
        default = null;
        description = "MCP (Model Context Protocol) server configurations";
      };
      formatter = mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            (lib.types.bool)
            (lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  disabled = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  command = mkOption {
                    type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                    default = null;
                  };
                  environment = mkOption {
                    type = lib.types.nullOr (lib.types.attrsOf (lib.types.str));
                    default = null;
                  };
                  extensions = mkOption {
                    type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                    default = null;
                  };
                };
              }
            ))
          ]
        );
        default = null;
        description = "Enable or configure formatters. Omit or set to false to disable, true to enable built-ins, or an object to enable built-ins with overrides.";
      };
      lsp = mkOption {
        type = lib.types.nullOr (
          lib.types.oneOf [
            (lib.types.bool)
            (lib.types.attrsOf (
              lib.types.oneOf [
                (lib.types.submodule {
                  options = {
                    disabled = mkOption {
                      type = lib.types.nullOr (lib.types.enum [ true ]);
                      default = null;
                    };
                  };
                })
                (lib.types.submodule {
                  options = {
                    command = mkOption {
                      type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                      default = null;
                    };
                    extensions = mkOption {
                      type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                      default = null;
                    };
                    disabled = mkOption {
                      type = lib.types.nullOr (lib.types.bool);
                      default = null;
                    };
                    env = mkOption {
                      type = lib.types.nullOr (lib.types.attrsOf (lib.types.str));
                      default = null;
                    };
                    initialization = mkOption {
                      type = lib.types.nullOr (lib.types.attrs);
                      default = null;
                    };
                  };
                })
              ]
            ))
          ]
        );
        default = null;
        description = "Enable or configure LSP servers. Omit or set to false to disable, true to enable built-ins, or an object to enable built-ins with overrides.";
      };
      instructions = mkOption {
        type = lib.types.nullOr (lib.types.listOf (lib.types.str));
        default = null;
        description = "Additional instruction files or patterns to include";
      };
      layout = mkOption {
        type = lib.types.nullOr (generatedTypes.LayoutConfig);
        default = null;
        description = "@deprecated Always uses stretch layout.";
      };
      permission = mkOption {
        type = lib.types.nullOr (generatedTypes.PermissionConfig);
        default = null;
      };
      tools = mkOption {
        type = lib.types.nullOr (lib.types.attrsOf (lib.types.bool));
        default = null;
      };
      attachment = mkOption {
        type = lib.types.nullOr (generatedTypes.AttachmentConfig);
        default = null;
        description = "Attachment processing configuration, including image size limits and resizing behavior";
      };
      enterprise = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              url = mkOption {
                type = lib.types.nullOr (lib.types.str);
                default = null;
                description = "Enterprise URL";
              };
            };
          }
        );
        default = null;
      };
      tool_output = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              max_lines = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
                default = null;
                description = "Maximum lines of tool output before it is truncated and saved to disk (default: 2000)";
              };
              max_bytes = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
                default = null;
                description = "Maximum bytes of tool output before it is truncated and saved to disk (default: 51200)";
              };
            };
          }
        );
        default = null;
        description = "Thresholds for truncating tool output. When output exceeds either limit, the full text is written to the truncation directory and a preview is returned.";
      };
      compaction = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              auto = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
                description = "Enable automatic compaction when context is full (default: true)";
              };
              prune = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
                description = "Enable pruning of old tool outputs (default: false)";
              };
              tail_turns = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x >= 0 && x <= 9007199254740991)));
                default = null;
                description = "Maximum number of recent user turns, including their following assistant/tool responses, to keep verbatim during compaction. By default retention is limited only by the preserved token budget.";
              };
              preserve_recent_tokens = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x >= 0 && x <= 9007199254740991)));
                default = null;
                description = "Maximum number of tokens from recent turns to preserve verbatim after compaction";
              };
              reserved = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x >= 0 && x <= 9007199254740991)));
                default = null;
                description = "Token buffer for compaction. Leaves enough window to avoid overflow during compaction.";
              };
            };
          }
        );
        default = null;
      };
      experimental = mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              disable_paste_summary = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
              };
              batch_tool = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
                description = "Enable the batch tool";
              };
              openTelemetry = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
                description = "Enable OpenTelemetry spans for AI SDK calls (using the 'experimental_telemetry' flag)";
              };
              primary_tools = mkOption {
                type = lib.types.nullOr (lib.types.listOf (lib.types.str));
                default = null;
                description = "Tools that should only be available to primary agents.";
              };
              continue_loop_on_deny = mkOption {
                type = lib.types.nullOr (lib.types.bool);
                default = null;
                description = "Continue the agent loop when a tool call is denied";
              };
              mcp_timeout = mkOption {
                type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
                default = null;
                description = "Timeout in milliseconds for model context protocol (MCP) requests";
              };
              policies = mkOption {
                type = lib.types.nullOr (lib.types.listOf (generatedTypes."ConfigV2.Experimental.Policy"));
                default = null;
                description = "Policy statements applied to supported resources, such as provider access";
              };
            };
          }
        );
        default = null;
      };
    };
  };
  generatedTypes = {
    LogLevel = lib.types.enum [
      "DEBUG"
      "INFO"
      "WARN"
      "ERROR"
    ];
    ServerConfig = lib.types.submodule {
      options = {
        port = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Port to listen on";
        };
        hostname = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "Hostname to listen on";
        };
        mdns = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
          description = "Enable mDNS service discovery";
        };
        mdnsDomain = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "Custom domain name for mDNS service (default: opencode.local)";
        };
        cors = mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.str));
          default = null;
          description = "Additional domains to allow for CORS";
        };
      };
    };
    "ConfigV2.Reference.Git" = lib.types.submodule {
      options = {
        repository = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        branch = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        description = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        hidden = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
        };
      };
    };
    "ConfigV2.Reference.Local" = lib.types.submodule {
      options = {
        path = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        description = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        hidden = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
        };
      };
    };
    PermissionActionConfig = lib.types.enum [
      "ask"
      "allow"
      "deny"
    ];
    PermissionObjectConfig = lib.types.attrsOf (generatedTypes.PermissionActionConfig);
    PermissionRuleConfig = lib.types.oneOf [
      (generatedTypes.PermissionActionConfig)
      (generatedTypes.PermissionObjectConfig)
    ];
    PermissionConfig = lib.types.oneOf [
      (generatedTypes.PermissionActionConfig)
      (lib.types.submodule {
        options = {
          read = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          edit = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          glob = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          grep = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          list = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          bash = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          task = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          external_directory = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          todowrite = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionActionConfig);
            default = null;
          };
          question = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionActionConfig);
            default = null;
          };
          webfetch = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionActionConfig);
            default = null;
          };
          websearch = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionActionConfig);
            default = null;
          };
          lsp = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
          doom_loop = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionActionConfig);
            default = null;
          };
          skill = mkOption {
            type = lib.types.nullOr (generatedTypes.PermissionRuleConfig);
            default = null;
          };
        };
        freeformType = lib.types.attrsOf (generatedTypes.PermissionRuleConfig);
      })
    ];
    AgentConfig = lib.types.submodule {
      options = {
        model = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        variant = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "Default model variant for this agent (applies only when using the agent's configured model).";
        };
        temperature = mkOption {
          type = lib.types.nullOr (lib.types.float);
          default = null;
        };
        top_p = mkOption {
          type = lib.types.nullOr (lib.types.float);
          default = null;
        };
        prompt = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        tools = mkOption {
          type = lib.types.nullOr (lib.types.attrsOf (lib.types.bool));
          default = null;
          description = "@deprecated Use 'permission' field instead";
        };
        disable = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
        };
        description = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "Description of when to use the agent";
        };
        mode = mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "subagent"
              "primary"
              "all"
            ]
          );
          default = null;
        };
        hidden = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
          description = "Hide this subagent from the @ autocomplete menu (default: false, only applies to mode: subagent)";
        };
        options = mkOption {
          type = lib.types.nullOr (lib.types.attrs);
          default = null;
        };
        color = mkOption {
          type = lib.types.nullOr (
            lib.types.oneOf [
              (lib.types.str)
              (lib.types.enum [
                "primary"
                "secondary"
                "accent"
                "success"
                "warning"
                "error"
                "info"
              ])
            ]
          );
          default = null;
          description = "Hex color code (e.g., #FF5733) or theme color (e.g., primary)";
        };
        steps = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Maximum number of agentic iterations before forcing text-only response";
        };
        maxSteps = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "@deprecated Use 'steps' field instead.";
        };
        permission = mkOption {
          type = lib.types.nullOr (generatedTypes.PermissionConfig);
          default = null;
        };
      };
    };
    ProviderConfig = lib.types.submodule {
      options = {
        api = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        name = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        env = mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.str));
          default = null;
        };
        id = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        npm = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
        whitelist = mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.str));
          default = null;
        };
        blacklist = mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.str));
          default = null;
        };
        options = mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                apiKey = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                baseURL = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                };
                enterpriseUrl = mkOption {
                  type = lib.types.nullOr (lib.types.str);
                  default = null;
                  description = "GitHub Enterprise URL for copilot authentication";
                };
                setCacheKey = mkOption {
                  type = lib.types.nullOr (lib.types.bool);
                  default = null;
                  description = "Enable promptCacheKey for this provider (default false)";
                };
                timeout = mkOption {
                  type = lib.types.nullOr (
                    lib.types.oneOf [
                      ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)))
                      (lib.types.enum [ false ])
                    ]
                  );
                  default = null;
                  description = "Timeout in milliseconds for full requests to this provider. Set to false to disable timeout.";
                };
                headerTimeout = mkOption {
                  type = lib.types.nullOr (
                    lib.types.oneOf [
                      ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)))
                      (lib.types.enum [ false ])
                    ]
                  );
                  default = null;
                  description = "Timeout in milliseconds to wait for response headers (default: 300000). Set to false to disable timeout.";
                };
                chunkTimeout = mkOption {
                  type = lib.types.nullOr (
                    lib.types.oneOf [
                      ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)))
                      (lib.types.enum [ false ])
                    ]
                  );
                  default = null;
                  description = "Timeout in milliseconds between streamed SSE chunks for this provider (default: 300000). If no chunk arrives within this window, the request is aborted. Set to false to disable timeout.";
                };
              };
            }
          );
          default = null;
        };
        models = mkOption {
          type = lib.types.nullOr (
            lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  id = mkOption {
                    type = lib.types.nullOr (lib.types.str);
                    default = null;
                  };
                  name = mkOption {
                    type = lib.types.nullOr (lib.types.str);
                    default = null;
                  };
                  family = mkOption {
                    type = lib.types.nullOr (lib.types.str);
                    default = null;
                  };
                  release_date = mkOption {
                    type = lib.types.nullOr (lib.types.str);
                    default = null;
                  };
                  attachment = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  reasoning = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  temperature = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  tool_call = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  interleaved = mkOption {
                    type = lib.types.nullOr (
                      lib.types.oneOf [
                        (lib.types.bool)
                        (lib.types.oneOf [
                          (lib.types.enum [
                            "reasoning"
                            "reasoning_content"
                            "reasoning_text"
                          ])
                          (lib.types.str)
                        ])
                        (lib.types.submodule {
                          options = {
                            field = mkOption {
                              type = lib.types.nullOr (
                                lib.types.oneOf [
                                  (lib.types.enum [
                                    "reasoning"
                                    "reasoning_content"
                                    "reasoning_text"
                                  ])
                                  (lib.types.str)
                                ]
                              );
                              default = null;
                            };
                          };
                        })
                      ]
                    );
                    default = null;
                  };
                  cost = mkOption {
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          input = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          output = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          cache_read = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          cache_write = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          context_over_200k = mkOption {
                            type = lib.types.nullOr (
                              lib.types.submodule {
                                options = {
                                  input = mkOption {
                                    type = lib.types.nullOr (lib.types.float);
                                    default = null;
                                  };
                                  output = mkOption {
                                    type = lib.types.nullOr (lib.types.float);
                                    default = null;
                                  };
                                  cache_read = mkOption {
                                    type = lib.types.nullOr (lib.types.float);
                                    default = null;
                                  };
                                  cache_write = mkOption {
                                    type = lib.types.nullOr (lib.types.float);
                                    default = null;
                                  };
                                };
                              }
                            );
                            default = null;
                          };
                        };
                      }
                    );
                    default = null;
                  };
                  limit = mkOption {
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          context = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          input = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                          output = mkOption {
                            type = lib.types.nullOr (lib.types.float);
                            default = null;
                          };
                        };
                      }
                    );
                    default = null;
                  };
                  modalities = mkOption {
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          input = mkOption {
                            type = lib.types.nullOr (
                              lib.types.listOf (
                                lib.types.enum [
                                  "text"
                                  "audio"
                                  "image"
                                  "video"
                                  "pdf"
                                ]
                              )
                            );
                            default = null;
                          };
                          output = mkOption {
                            type = lib.types.nullOr (
                              lib.types.listOf (
                                lib.types.enum [
                                  "text"
                                  "audio"
                                  "image"
                                  "video"
                                  "pdf"
                                ]
                              )
                            );
                            default = null;
                          };
                        };
                      }
                    );
                    default = null;
                  };
                  experimental = mkOption {
                    type = lib.types.nullOr (lib.types.bool);
                    default = null;
                  };
                  status = mkOption {
                    type = lib.types.nullOr (
                      lib.types.enum [
                        "alpha"
                        "beta"
                        "deprecated"
                        "active"
                      ]
                    );
                    default = null;
                  };
                  provider = mkOption {
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          npm = mkOption {
                            type = lib.types.nullOr (lib.types.str);
                            default = null;
                          };
                          api = mkOption {
                            type = lib.types.nullOr (lib.types.str);
                            default = null;
                          };
                        };
                      }
                    );
                    default = null;
                  };
                  options = mkOption {
                    type = lib.types.nullOr (lib.types.attrs);
                    default = null;
                  };
                  headers = mkOption {
                    type = lib.types.nullOr (lib.types.attrsOf (lib.types.str));
                    default = null;
                  };
                  variants = mkOption {
                    type = lib.types.nullOr (
                      lib.types.attrsOf (
                        lib.types.submodule {
                          options = {
                            disabled = mkOption {
                              type = lib.types.nullOr (lib.types.bool);
                              default = null;
                              description = "Disable this variant for the model";
                            };
                          };
                        }
                      )
                    );
                    default = null;
                    description = "Variant-specific configuration";
                  };
                };
              }
            )
          );
          default = null;
        };
      };
    };
    McpLocalConfig = lib.types.submodule {
      options = {
        type = mkOption {
          type = lib.types.nullOr (lib.types.enum [ "local" ]);
          default = null;
          description = "Type of MCP server connection";
        };
        command = mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.str));
          default = null;
          description = "Command and arguments to run the MCP server";
        };
        cwd = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "Working directory for the MCP server process. Relative paths resolve from the workspace directory.";
        };
        environment = mkOption {
          type = lib.types.nullOr (lib.types.attrsOf (lib.types.str));
          default = null;
          description = "Environment variables to set when running the MCP server";
        };
        enabled = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
          description = "Enable or disable the MCP server on startup";
        };
        timeout = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Timeout in ms for MCP server requests. Defaults to 5000 (5 seconds) if not specified.";
        };
      };
    };
    McpOAuthConfig = lib.types.submodule {
      options = {
        clientId = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "OAuth client ID. If not provided, dynamic client registration (RFC 7591) will be attempted.";
        };
        clientSecret = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "OAuth client secret (if required by the authorization server)";
        };
        scope = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "OAuth scopes to request during authorization";
        };
        callbackPort = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x >= 1 && x <= 65535)));
          default = null;
          description = "Port for the local OAuth callback server (default: 19876). Shorthand for redirectUri when only the port needs changing. Ignored if redirectUri is set.";
        };
        redirectUri = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "OAuth redirect URI (default: http://127.0.0.1:19876/mcp/oauth/callback).";
        };
      };
    };
    McpRemoteConfig = lib.types.submodule {
      options = {
        type = mkOption {
          type = lib.types.nullOr (lib.types.enum [ "remote" ]);
          default = null;
          description = "Type of MCP server connection";
        };
        url = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
          description = "URL of the remote MCP server";
        };
        enabled = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
          description = "Enable or disable the MCP server on startup";
        };
        headers = mkOption {
          type = lib.types.nullOr (lib.types.attrsOf (lib.types.str));
          default = null;
          description = "Headers to send with the request";
        };
        oauth = mkOption {
          type = lib.types.nullOr (
            lib.types.oneOf [
              (generatedTypes.McpOAuthConfig)
              (lib.types.enum [ false ])
            ]
          );
          default = null;
          description = "OAuth authentication configuration for the MCP server. Set to false to disable OAuth auto-detection.";
        };
        timeout = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Timeout in ms for MCP server requests. Defaults to 5000 (5 seconds) if not specified.";
        };
      };
    };
    LayoutConfig = lib.types.enum [
      "auto"
      "stretch"
    ];
    ImageAttachmentConfig = lib.types.submodule {
      options = {
        auto_resize = mkOption {
          type = lib.types.nullOr (lib.types.bool);
          default = null;
          description = "Resize images before sending them to the model when they exceed configured limits (default: true)";
        };
        max_width = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Maximum image width before resizing or rejecting the attachment (default: 2000)";
        };
        max_height = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Maximum image height before resizing or rejecting the attachment (default: 2000)";
        };
        max_base64_bytes = mkOption {
          type = lib.types.nullOr ((lib.types.addCheck lib.types.int (x: x <= 9007199254740991 && x > 0)));
          default = null;
          description = "Maximum base64 payload bytes for an image attachment (default: 5242880)";
        };
      };
    };
    AttachmentConfig = lib.types.submodule {
      options = {
        image = mkOption {
          type = lib.types.nullOr (generatedTypes.ImageAttachmentConfig);
          default = null;
          description = "Image attachment configuration";
        };
      };
    };
    "Policy.Effect" = lib.types.enum [
      "allow"
      "deny"
    ];
    "ConfigV2.Experimental.Policy" = lib.types.submodule {
      options = {
        action = mkOption {
          type = lib.types.nullOr (
            lib.types.oneOf [ (lib.types.oneOf [ (lib.types.enum [ "provider.use" ]) ]) ]
          );
          default = null;
        };
        effect = mkOption {
          type = lib.types.nullOr (generatedTypes."Policy.Effect");
          default = null;
        };
        resource = mkOption {
          type = lib.types.nullOr (lib.types.str);
          default = null;
        };
      };
    };
    Config = lib.types.submodule {
      options = options.Config;
    };
  };
in
{
  inherit generatedTypes options;
  types = generatedTypes;
}
