defmodule Tuist.Docs.Sidebar do
  @moduledoc """
  Defines the navigation sidebar tree for the documentation pages.
  Mirrors the structure from docs/.vitepress/bars.mjs.
  """

  defmodule Item do
    @moduledoc false
    defstruct [:label, :slug, :icon, :url, items: []]
  end

  defmodule Group do
    @moduledoc false
    defstruct [:label, weight: :semibold, items: []]
  end

  @strings_dir Path.expand("../../../docs/.vitepress/strings", __DIR__)

  extract_texts = fn extract_texts, map, prefix ->
    map
    |> Enum.flat_map(fn
      {"text", value} when is_binary(value) ->
        [{prefix |> Enum.reverse() |> Enum.join("."), value}]

      {key, value} when is_map(value) ->
        extract_texts.(extract_texts, value, [key | prefix])

      _ ->
        []
    end)
    |> Map.new()
  end

  en_path = Path.join(@strings_dir, "en.json")

  translations =
    if File.exists?(en_path) do
      {:ok, en_content} = File.read(en_path)
      {:ok, en_data} = JSON.decode(en_content)
      en_strings = extract_texts.(extract_texts, en_data, [])

      @strings_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) == "en.json"))
      |> Map.new(fn path ->
        locale = Path.basename(path, ".json")
        {:ok, content} = File.read(path)
        {:ok, data} = JSON.decode(content)
        locale_texts = extract_texts.(extract_texts, data, [])

        label_map =
          Map.new(en_strings, fn {text_path, en_text} ->
            {en_text, Map.get(locale_texts, text_path, en_text)}
          end)

        {locale, label_map}
      end)
    else
      %{}
    end

  @translations translations

  def tree do
    guides_tree() ++ resources_tree() ++ references_tree()
  end

  def tab_for_slug(slug) do
    path = Regex.replace(~r{^/[^/]+/}, slug, "/")

    cond do
      String.starts_with?(path, "/references") -> :references
      String.starts_with?(path, "/contributors") -> :resources
      true -> :guides
    end
  end

  def tree_for_tab(tab, locale \\ "en")
  def tree_for_tab(:guides, locale), do: localize_tree(guides_tree(), locale)
  def tree_for_tab(:references, locale), do: localize_tree(references_tree(), locale)
  def tree_for_tab(:resources, locale), do: localize_tree(resources_tree(), locale)

  defp localize_tree(tree, "en"), do: tree

  defp localize_tree(tree, locale) do
    label_map = Map.get(@translations, locale, %{})

    Enum.map(tree, fn
      %Group{label: label, items: items} = group ->
        %{group | label: translate(label, label_map), items: Enum.map(items, &localize_item(&1, locale, label_map))}
    end)
  end

  defp localize_item(%Item{slug: nil, label: label, items: items} = item, locale, label_map) do
    %{item | label: translate(label, label_map), items: Enum.map(items, &localize_item(&1, locale, label_map))}
  end

  defp localize_item(%Item{slug: "/en/" <> rest, label: label, items: items} = item, locale, label_map) do
    %{
      item
      | slug: "/#{locale}/#{rest}",
        label: translate(label, label_map),
        items: Enum.map(items, &localize_item(&1, locale, label_map))
    }
  end

  defp localize_item(%Item{label: label, items: items} = item, locale, label_map) do
    %{item | label: translate(label, label_map), items: Enum.map(items, &localize_item(&1, locale, label_map))}
  end

  defp translate(nil, _label_map), do: nil
  defp translate(label, label_map), do: Map.get(label_map, label, label)

  def item_active?(%Item{slug: slug}, current_slug) when is_binary(slug), do: slug == current_slug

  def item_active?(%Item{}, _current_slug), do: false

  def item_or_children_active?(%Item{slug: slug, items: items}, current_slug) do
    slug == current_slug or Enum.any?(items, &item_or_children_active?(&1, current_slug))
  end

  def guides_tree do
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
        label: "Builds",
        weight: :medium,
        items: [
          %Item{
            label: "Cache",
            slug: "/en/guides/features/cache",
            items: [
              %Item{label: "Xcode cache", slug: "/en/guides/features/cache/xcode-cache", icon: "xcode"},
              %Item{label: "Module cache", slug: "/en/guides/features/cache/module-cache", icon: "xcode"},
              %Item{label: "Gradle cache", slug: "/en/guides/features/cache/gradle-cache", icon: "gradle"}
            ]
          },
          %Item{
            label: "Build insights",
            slug: "/en/guides/features/build-insights",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/build-insights/xcode", icon: "xcode"},
              %Item{label: "Gradle", slug: "/en/guides/features/build-insights/gradle", icon: "gradle"}
            ]
          }
        ]
      },
      %Group{
        label: "Tests",
        weight: :medium,
        items: [
          %Item{label: "Selective testing", slug: "/en/guides/features/selective-testing"},
          %Item{
            label: "Test insights",
            slug: "/en/guides/features/test-insights",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/test-insights/xcode", icon: "xcode"},
              %Item{label: "Gradle", slug: "/en/guides/features/test-insights/gradle", icon: "gradle"}
            ]
          },
          %Item{
            label: "Flaky tests",
            slug: "/en/guides/features/test-insights/flaky-tests",
            items: [
              %Item{
                label: "Xcode",
                slug: "/en/guides/features/test-insights/flaky-tests/xcode",
                icon: "xcode"
              },
              %Item{
                label: "Gradle",
                slug: "/en/guides/features/test-insights/flaky-tests/gradle",
                icon: "gradle"
              }
            ]
          },
          %Item{
            label: "Test sharding",
            slug: "/en/guides/features/test-sharding",
            items: [
              %Item{label: "Xcode", slug: "/en/guides/features/test-sharding/xcode", icon: "xcode"},
              %Item{
                label: "Generated projects",
                slug: "/en/guides/features/test-sharding/generated-projects",
                icon: "xcode"
              },
              %Item{label: "Gradle", slug: "/en/guides/features/test-sharding/gradle", icon: "gradle"}
            ]
          }
        ]
      },
      %Group{
        label: "Artifacts",
        weight: :medium,
        items: [
          %Item{label: "Previews", slug: "/en/guides/features/previews"},
          %Item{label: "Bundle size", slug: "/en/guides/features/bundle-size"}
        ]
      },
      %Group{
        label: "Other features",
        weight: :medium,
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

  def resources_tree do
    [
      %Group{
        label: nil,
        items: [
          %Item{label: "Changelog", url: "https://github.com/tuist/tuist/releases"},
          %Item{label: "API documentation", url: "https://tuist.dev/api/docs"},
          %Item{label: "Status", url: "https://status.tuist.io"},
          %Item{
            label: "Metrics dashboard",
            url: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9"
          }
        ]
      },
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

  @example_tuples Tuist.Docs.Loader.load_example_items!()

  def references_tree do
    example_items =
      Enum.map(@example_tuples, fn {title, slug} -> %Item{label: title, slug: slug} end)

    [
      %Group{
        label: "Examples",
        items: [
          %Item{
            label: "Generated projects",
            slug: "/en/references/examples/generated-projects",
            items: example_items
          }
        ]
      },
      %Group{
        label: "References",
        items: [
          %Item{label: "tuist.toml", slug: "/en/references/tuist-toml"},
          %Item{
            label: "Project description",
            url: "https://tuist.dev/api/docs"
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
