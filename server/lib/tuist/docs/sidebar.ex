defmodule Tuist.Docs.Sidebar do
  @moduledoc false
  def guides_sidebar do
    [
      %{
        text: "Guides",
        items: [
          %{text: "Install Tuist", link: "/docs/guides/install-tuist"},
          %{text: "Install the Gradle plugin", link: "/docs/guides/install-gradle-plugin"}
        ]
      },
      %{
        text: "Tutorials",
        items: [
          %{
            text: "Xcode",
            items: [
              %{text: "Create a generated project", link: "/docs/tutorials/xcode/create-a-generated-project"}
            ]
          }
        ]
      },
      %{
        text: "Features",
        items: [
          %{
            text: "Generated projects",
            link: "/docs/guides/features/projects",
            collapsed: true,
            items: [
              %{
                text: "Adoption",
                collapsed: true,
                items: [
                  %{text: "Create a new project", link: "/docs/guides/features/projects/adoption/new-project"},
                  %{text: "Try with a Swift Package", link: "/docs/guides/features/projects/adoption/swift-package"},
                  %{
                    text: "Migrate",
                    collapsed: true,
                    items: [
                      %{text: "An Xcode project", link: "/docs/guides/features/projects/adoption/migrate/xcode-project"},
                      %{text: "A Swift package", link: "/docs/guides/features/projects/adoption/migrate/swift-package"},
                      %{
                        text: "An XcodeGen project",
                        link: "/docs/guides/features/projects/adoption/migrate/xcodegen-project"
                      },
                      %{text: "A Bazel project", link: "/docs/guides/features/projects/adoption/migrate/bazel-project"}
                    ]
                  }
                ]
              },
              %{text: "Manifests", link: "/docs/guides/features/projects/manifests"},
              %{text: "Directory structure", link: "/docs/guides/features/projects/directory-structure"},
              %{text: "Editing", link: "/docs/guides/features/projects/editing"},
              %{text: "Dependencies", link: "/docs/guides/features/projects/dependencies"},
              %{text: "Code sharing", link: "/docs/guides/features/projects/code-sharing"},
              %{text: "Synthesized files", link: "/docs/guides/features/projects/synthesized-files"},
              %{text: "Dynamic configuration", link: "/docs/guides/features/projects/dynamic-configuration"},
              %{text: "Templates", link: "/docs/guides/features/projects/templates"},
              %{text: "Plugins", link: "/docs/guides/features/projects/plugins"},
              %{text: "Hashing", link: "/docs/guides/features/projects/hashing"},
              %{
                text: "Inspect",
                collapsed: true,
                items: [
                  %{text: "Implicit imports", link: "/docs/guides/features/projects/inspect/implicit-dependencies"}
                ]
              },
              %{text: "The cost of convenience", link: "/docs/guides/features/projects/cost-of-convenience"},
              %{text: "Modular architecture", link: "/docs/guides/features/projects/tma-architecture"},
              %{text: "Metadata tags", link: "/docs/guides/features/projects/metadata-tags"},
              %{text: "Best practices", link: "/docs/guides/features/projects/best-practices"}
            ]
          },
          %{
            text: "Cache",
            link: "/docs/guides/features/cache",
            collapsed: true,
            items: [
              %{
                text: "Xcode",
                collapsed: true,
                items: [
                  %{text: "Xcode cache", link: "/docs/guides/features/cache/xcode-cache"},
                  %{text: "Module cache", link: "/docs/guides/features/cache/module-cache"}
                ]
              },
              %{text: "Gradle cache", link: "/docs/guides/features/cache/gradle-cache"}
            ]
          },
          %{text: "Selective testing", link: "/docs/guides/features/selective-testing"},
          %{
            text: "Registry",
            link: "/docs/guides/features/registry",
            collapsed: true,
            items: [
              %{text: "Xcode project", link: "/docs/guides/features/registry/xcode-project"},
              %{text: "Generated project", link: "/docs/guides/features/registry/generated-project"},
              %{text: "XcodeProj-based integration", link: "/docs/guides/features/registry/xcodeproj-integration"},
              %{text: "Swift package", link: "/docs/guides/features/registry/swift-package"},
              %{text: "Continuous integration", link: "/docs/guides/features/registry/continuous-integration"}
            ]
          },
          %{
            text: "Build insights",
            link: "/docs/guides/features/insights",
            collapsed: true,
            items: [
              %{text: "Xcode", link: "/docs/guides/features/insights/xcode-cache"},
              %{text: "Gradle", link: "/docs/guides/features/insights/gradle-cache"}
            ]
          },
          %{
            text: "Test insights",
            link: "/docs/guides/features/test-insights",
            collapsed: true,
            items: [
              %{text: "Xcode", link: "/docs/guides/features/test-insights/xcode"},
              %{text: "Gradle", link: "/docs/guides/features/test-insights/gradle"}
            ]
          },
          %{
            text: "Flaky tests",
            link: "/docs/guides/features/test-insights/flaky-tests",
            collapsed: true,
            items: [
              %{text: "Xcode", link: "/docs/guides/features/test-insights/flaky-tests/xcode"},
              %{text: "Gradle", link: "/docs/guides/features/test-insights/flaky-tests/gradle"}
            ]
          },
          %{text: "Bundle insights", link: "/docs/guides/features/bundle-size"},
          %{text: "QA", link: "/docs/guides/features/qa"},
          %{text: "Previews", link: "/docs/guides/features/previews"},
          %{
            text: "Agentic Coding",
            collapsed: true,
            items: [
              %{text: "Skills", link: "/docs/guides/features/agentic-coding/skills"}
            ]
          }
        ]
      },
      %{
        text: "Integrations",
        items: [
          %{text: "Continuous integration", link: "/docs/guides/integrations/continuous-integration"},
          %{text: "SSO", link: "/docs/guides/integrations/sso"},
          %{text: "Slack", link: "/docs/guides/integrations/slack"},
          %{
            text: "Git forges",
            collapsed: true,
            items: [
              %{text: "GitHub", link: "/docs/guides/integrations/gitforge/github"}
            ]
          }
        ]
      },
      %{
        text: "Server",
        items: [
          %{text: "Accounts and projects", link: "/docs/guides/server/accounts-and-projects"},
          %{text: "Authentication", link: "/docs/guides/server/authentication"},
          %{
            text: "Self-hosting",
            collapsed: true,
            items: [
              %{text: "Installation", link: "/docs/guides/server/self-host/install"},
              %{text: "Cache nodes", link: "/docs/guides/cache/self-host"},
              %{text: "Cache architecture", link: "/docs/guides/cache/architecture"},
              %{text: "Telemetry", link: "/docs/guides/server/self-host/telemetry"}
            ]
          }
        ]
      }
    ]
  end

  def contributors_sidebar do
    [
      %{
        text: "Contributors",
        items: [
          %{
            text: "Code",
            link: "/docs/contributors/code",
            collapsed: true,
            items: [
              %{text: "CLI", link: "/docs/contributors/code/cli"},
              %{text: "Server", link: "/docs/contributors/code/server"},
              %{text: "Handbook", link: "/docs/contributors/code/handbook"},
              %{text: "Docs", link: "/docs/contributors/code/docs"}
            ]
          },
          %{text: "Issue reporting", link: "/docs/contributors/issue-reporting"},
          %{text: "Code reviews", link: "/docs/contributors/code-reviews"},
          %{text: "Principles", link: "/docs/contributors/principles"},
          %{text: "Debugging", link: "/docs/contributors/debugging"},
          %{text: "Translate", link: "/docs/contributors/translate"},
          %{text: "Releases", link: "/docs/contributors/releases"},
          %{
            text: "CLI",
            collapsed: true,
            items: [
              %{text: "Logging", link: "/docs/contributors/cli/logging"}
            ]
          }
        ]
      }
    ]
  end

  def references_sidebar do
    [
      %{
        text: "Configuration",
        items: [
          %{text: "tuist.toml", link: "/docs/references/tuist-toml"}
        ]
      },
      %{
        text: "Xcode",
        items: [
          %{
            text: "Generated Projects",
            collapsed: true,
            items: [
              %{
                text: "Migrations",
                collapsed: true,
                items: [
                  %{text: "From v3 to v4", link: "/docs/references/migrations/from-v3-to-v4"}
                ]
              }
            ]
          }
        ]
      }
    ]
  end

  def sidebar_for_slug(slug) do
    cond do
      String.starts_with?(slug, "/docs/contributors") -> contributors_sidebar()
      String.starts_with?(slug, "/docs/references") -> references_sidebar()
      true -> guides_sidebar()
    end
  end
end
