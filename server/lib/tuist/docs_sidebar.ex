defmodule Tuist.Docs.Sidebar do
  @moduledoc """
  Defines the navigation sidebar tree for the documentation pages.
  Mirrors the structure from docs/.vitepress/bars.mjs.
  """

  defmodule Item do
    @moduledoc false
    defstruct [:label, :slug, items: []]
  end

  defmodule Group do
    @moduledoc false
    defstruct [:label, items: []]
  end

  def tree do
    guides_tree() ++ contributors_tree() ++ references_tree()
  end

  def item_active?(%Item{slug: slug}, current_slug) when is_binary(slug), do: slug == current_slug

  def item_active?(%Item{}, _current_slug), do: false

  def item_or_children_active?(%Item{slug: slug, items: items}, current_slug) do
    slug == current_slug or Enum.any?(items, &item_or_children_active?(&1, current_slug))
  end

  defp guides_tree do
    [
      %Group{
        label: "Guides",
        items: [
          %Item{label: "Install Tuist", slug: "/en/guides/install-tuist"},
          %Item{label: "Install the Gradle plugin", slug: "/en/guides/install-gradle-plugin"}
        ]
      },
      %Group{
        label: "Tutorials",
        items: [
          %Item{
            label: "Xcode",
            items: [
              %Item{
                label: "Create a generated project",
                slug: "/en/tutorials/xcode/create-a-generated-project"
              }
            ]
          }
        ]
      },
      %Group{
        label: "Features",
        items: [
          %Item{
            label: "Generated projects",
            slug: "/en/guides/features/projects",
            items: [
              %Item{
                label: "Adoption",
                items: [
                  %Item{
                    label: "New project",
                    slug: "/en/guides/features/projects/adoption/new-project"
                  },
                  %Item{
                    label: "Swift package",
                    slug: "/en/guides/features/projects/adoption/swift-package"
                  },
                  %Item{
                    label: "Migrate",
                    items: [
                      %Item{
                        label: "Xcode project",
                        slug: "/en/guides/features/projects/adoption/migrate/xcode-project"
                      },
                      %Item{
                        label: "Swift package",
                        slug: "/en/guides/features/projects/adoption/migrate/swift-package"
                      },
                      %Item{
                        label: "XcodeGen project",
                        slug: "/en/guides/features/projects/adoption/migrate/xcodegen-project"
                      },
                      %Item{
                        label: "Bazel project",
                        slug: "/en/guides/features/projects/adoption/migrate/bazel-project"
                      }
                    ]
                  }
                ]
              },
              %Item{label: "Manifests", slug: "/en/guides/features/projects/manifests"},
              %Item{
                label: "Directory structure",
                slug: "/en/guides/features/projects/directory-structure"
              },
              %Item{label: "Editing", slug: "/en/guides/features/projects/editing"},
              %Item{label: "Dependencies", slug: "/en/guides/features/projects/dependencies"},
              %Item{label: "Code sharing", slug: "/en/guides/features/projects/code-sharing"},
              %Item{
                label: "Synthesized files",
                slug: "/en/guides/features/projects/synthesized-files"
              },
              %Item{
                label: "Dynamic configuration",
                slug: "/en/guides/features/projects/dynamic-configuration"
              },
              %Item{label: "Templates", slug: "/en/guides/features/projects/templates"},
              %Item{label: "Plugins", slug: "/en/guides/features/projects/plugins"},
              %Item{label: "Hashing", slug: "/en/guides/features/projects/hashing"},
              %Item{
                label: "Inspect",
                items: [
                  %Item{
                    label: "Implicit dependencies",
                    slug: "/en/guides/features/projects/inspect/implicit-dependencies"
                  }
                ]
              },
              %Item{
                label: "The cost of convenience",
                slug: "/en/guides/features/projects/cost-of-convenience"
              },
              %Item{
                label: "uFeatures architecture",
                slug: "/en/guides/features/projects/tma-architecture"
              },
              %Item{label: "Metadata tags", slug: "/en/guides/features/projects/metadata-tags"},
              %Item{label: "Best practices", slug: "/en/guides/features/projects/best-practices"}
            ]
          },
          %Item{
            label: "Cache",
            slug: "/en/guides/features/cache",
            items: [
              %Item{label: "Xcode cache", slug: "/en/guides/features/cache/xcode-cache"},
              %Item{label: "Module cache", slug: "/en/guides/features/cache/module-cache"},
              %Item{label: "Gradle cache", slug: "/en/guides/features/cache/gradle-cache"}
            ]
          },
          %Item{label: "Selective testing", slug: "/en/guides/features/selective-testing"},
          %Item{
            label: "Registry",
            slug: "/en/guides/features/registry",
            items: [
              %Item{label: "Xcode project", slug: "/en/guides/features/registry/xcode-project"},
              %Item{
                label: "Generated project",
                slug: "/en/guides/features/registry/generated-project"
              },
              %Item{
                label: "Xcodeproj integration",
                slug: "/en/guides/features/registry/xcodeproj-integration"
              },
              %Item{
                label: "Swift package",
                slug: "/en/guides/features/registry/swift-package"
              },
              %Item{
                label: "Continuous integration",
                slug: "/en/guides/features/registry/continuous-integration"
              }
            ]
          },
          %Item{
            label: "Insights",
            slug: "/en/guides/features/insights",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/insights/xcode-cache"},
              %Item{label: "Gradle", slug: "/en/guides/features/insights/gradle-cache"}
            ]
          },
          %Item{
            label: "Test insights",
            slug: "/en/guides/features/test-insights",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/test-insights/xcode"},
              %Item{label: "Gradle", slug: "/en/guides/features/test-insights/gradle"}
            ]
          },
          %Item{
            label: "Flaky tests",
            slug: "/en/guides/features/test-insights/flaky-tests",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/test-insights/flaky-tests/xcode"},
              %Item{
                label: "Gradle",
                slug: "/en/guides/features/test-insights/flaky-tests/gradle"
              }
            ]
          },
          %Item{label: "Bundle size", slug: "/en/guides/features/bundle-size"},
          %Item{label: "QA", slug: "/en/guides/features/qa"},
          %Item{label: "Previews", slug: "/en/guides/features/previews"},
          %Item{
            label: "Agentic coding",
            items: [
              %Item{label: "MCP", slug: "/en/guides/features/agentic-coding/mcp"},
              %Item{label: "Skills", slug: "/en/guides/features/agentic-coding/skills"}
            ]
          }
        ]
      },
      %Group{
        label: "Integrations",
        items: [
          %Item{
            label: "Continuous integration",
            slug: "/en/guides/integrations/continuous-integration"
          },
          %Item{label: "SSO", slug: "/en/guides/integrations/sso"},
          %Item{label: "Slack", slug: "/en/guides/integrations/slack"},
          %Item{
            label: "Git forges",
            items: [
              %Item{label: "GitHub", slug: "/en/guides/integrations/gitforge/github"}
            ]
          }
        ]
      },
      %Group{
        label: "Server",
        items: [
          %Item{
            label: "Accounts and projects",
            slug: "/en/guides/server/accounts-and-projects"
          },
          %Item{label: "Authentication", slug: "/en/guides/server/authentication"},
          %Item{label: "Network", slug: "/en/guides/server/network"},
          %Item{
            label: "Self-hosting",
            items: [
              %Item{label: "Installation", slug: "/en/guides/server/self-host/install"},
              %Item{label: "Cache nodes", slug: "/en/guides/cache/self-host"},
              %Item{label: "Cache architecture", slug: "/en/guides/cache/architecture"},
              %Item{label: "Telemetry", slug: "/en/guides/server/self-host/telemetry"}
            ]
          }
        ]
      }
    ]
  end

  defp contributors_tree do
    [
      %Group{
        label: "Contributors",
        items: [
          %Item{
            label: "Code",
            slug: "/en/contributors/code",
            items: [
              %Item{label: "CLI", slug: "/en/contributors/code/cli"},
              %Item{label: "Server", slug: "/en/contributors/code/server"},
              %Item{label: "Handbook", slug: "/en/contributors/code/handbook"},
              %Item{label: "Docs", slug: "/en/contributors/code/docs"}
            ]
          },
          %Item{label: "Issue reporting", slug: "/en/contributors/issue-reporting"},
          %Item{label: "Code reviews", slug: "/en/contributors/code-reviews"},
          %Item{label: "Principles", slug: "/en/contributors/principles"},
          %Item{label: "Debugging", slug: "/en/contributors/debugging"},
          %Item{label: "Translate", slug: "/en/contributors/translate"},
          %Item{label: "Releases", slug: "/en/contributors/releases"},
          %Item{
            label: "CLI",
            items: [
              %Item{label: "Logging", slug: "/en/contributors/cli/logging"}
            ]
          }
        ]
      }
    ]
  end

  defp references_tree do
    [
      %Group{
        label: "References",
        items: [
          %Item{label: "tuist.toml", slug: "/en/references/tuist-toml"},
          %Item{label: "Examples", slug: "/en/references/examples"},
          %Item{
            label: "Generated projects",
            slug: "/en/references/examples/generated-projects"
          },
          %Item{
            label: "Migrations",
            items: [
              %Item{label: "From v3 to v4", slug: "/en/references/migrations/from-v3-to-v4"}
            ]
          }
        ]
      }
    ]
  end
end
