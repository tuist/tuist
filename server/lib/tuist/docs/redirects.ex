defmodule Tuist.Docs.Redirects do
  @moduledoc """
  Source of truth for documentation URL redirects.

  Rules are evaluated against the logical docs path, the portion after
  `/<locale>/docs`.
  """

  alias Tuist.Docs.Paths
  alias Tuist.Locale

  @docs_path_regex ~r{^/(?<locale>[^/]+)/docs(?<rest>/.*)?$}
  @supported_locales Locale.supported_locales()
  @legacy_english_fallback_locales ["ar", "pl", "pt"]

  @rules [
    # Legacy docs.tuist.io pages
    {:exact, "/documentation/tuist/installation", "/guides/install-tuist"},
    {:exact, "/documentation/tuist/project-structure", "/guides/features/projects/directory-structure"},
    {:exact, "/documentation/tuist/command-line-interface", "/cli"},
    {:exact, "/documentation/tuist/dependencies", "/guides/features/projects/dependencies"},
    {:exact, "/documentation/tuist/sharing-code-across-manifests", "/guides/features/projects/code-sharing"},
    {:exact, "/documentation/tuist/synthesized-files", "/guides/features/projects/synthesized-files"},
    {:exact, "/documentation/tuist/migration-guidelines", "/guides/features/projects/adoption/migrate/xcode-project"},
    {:exact, "/documentation/tuist/generation-environment", "/guides/features/projects/dynamic-configuration"},
    {:exact, "/documentation/tuist/using-plugins", "/guides/features/projects/plugins"},
    {:exact, "/documentation/tuist/creating-plugins", "/guides/features/projects/plugins"},
    {:exact, "/documentation/tuist/task", "/guides/features/projects/plugins"},
    {:exact, "/documentation/tuist/tuist-cloud", "/"},
    {:exact, "/documentation/tuist/tuist-cloud-get-started", "/"},
    {:exact, "/documentation/tuist/binary-caching", "/guides/features/cache"},
    {:exact, "/documentation/tuist/selective-testing", "/guides/features/selective-testing"},
    {:exact, "/documentation/tuist/get-started-as-contributor", "/contributors/code"},
    {:exact, "/documentation/tuist/manifesto", "/contributors/principles"},
    {:exact, "/documentation/tuist/code-reviews", "/contributors/code-reviews"},
    {:exact, "/documentation/tuist/reporting-bugs", "/contributors/issue-reporting"},
    {:exact, "/documentation/tuist/championing-projects", "/contributors/code"},
    {:prefix_discard, "/documentation/tuist/", "/"},

    # Legacy tutorials
    {:exact, "/tutorials/tuist-tutorials", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/tuist/install", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/tuist/create-project", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/tuist/external-dependencies", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/tuist-cloud-tutorials", "/guides/server/self-host/install"},
    {:exact, "/tutorials/tuist/enterprise-infrastructure-requirements", "/guides/server/self-host/install"},
    {:exact, "/tutorials/tuist/enterprise-environment", "/guides/server/self-host/install"},
    {:exact, "/tutorials/tuist/enterprise-deployment", "/guides/server/self-host/install"},

    # Legacy guide structure
    {:exact, "/contributors/get-started", "/contributors/code"},
    {:exact, "/guide/scale/ufeatures-architecture.html", "/guides/features/projects/tma-architecture"},
    {:exact, "/guide/scale/ufeatures-architecture", "/guides/features/projects/tma-architecture"},
    {:exact, "/guide/introduction/cost-of-convenience", "/guides/features/projects/cost-of-convenience"},
    {:exact, "/guide/introduction/installation", "/guides/install-tuist"},
    {:exact, "/guide/introduction/adopting-tuist/new-project", "/guides/features/projects/adoption/new-project"},
    {:exact, "/guide/introduction/adopting-tuist/swift-package", "/guides/features/projects/adoption/swift-package"},
    {:exact, "/guide/introduction/adopting-tuist/migrate-from-xcodeproj",
     "/guides/features/projects/adoption/migrate/xcode-project"},
    {:exact, "/guide/introduction/adopting-tuist/migrate-local-swift-packages",
     "/guides/features/projects/adoption/migrate/swift-package"},
    {:exact, "/guide/introduction/adopting-tuist/migrate-from-xcodegen",
     "/guides/features/projects/adoption/migrate/xcodegen-project"},
    {:exact, "/guide/introduction/adopting-tuist/migrate-from-bazel",
     "/guides/features/projects/adoption/migrate/bazel-project"},
    {:exact, "/guide/introduction/from-v3-to-v4", "/references/migrations/from-v3-to-v4"},
    {:exact, "/guide/project/manifests", "/guides/features/projects/manifests"},
    {:exact, "/guide/project/directory-structure", "/guides/features/projects/directory-structure"},
    {:exact, "/guide/project/editing", "/guides/features/projects/editing"},
    {:exact, "/guide/project/dependencies", "/guides/features/projects/dependencies"},
    {:exact, "/guide/project/code-sharing", "/guides/features/projects/code-sharing"},
    {:exact, "/guide/project/synthesized-files", "/guides/features/projects/synthesized-files"},
    {:exact, "/guide/project/dynamic-configuration", "/guides/features/projects/dynamic-configuration"},
    {:exact, "/guide/project/templates", "/guides/features/projects/templates"},
    {:exact, "/guide/project/plugins", "/guides/features/projects/plugins"},
    {:exact, "/guide/automation/generate", "/"},
    {:exact, "/guide/automation/build", "/guides/features/cache"},
    {:exact, "/guide/automation/test", "/guides/features/selective-testing"},
    {:exact, "/guide/automation/run", "/cli"},
    {:exact, "/guide/automation/graph", "/cli"},
    {:exact, "/guide/automation/clean", "/cli"},
    {:exact, "/guide/scale/tma-architecture", "/guides/features/projects/tma-architecture"},

    # Legacy cloud pages
    {:exact, "/cloud/what-is-cloud", "/"},
    {:exact, "/cloud/get-started", "/"},
    {:exact, "/cloud/binary-caching", "/guides/features/cache"},
    {:exact, "/cloud/selective-testing", "/guides/features/selective-testing"},
    {:exact, "/cloud/hashing", "/guides/features/projects/hashing"},
    {:exact, "/cloud/on-premise", "/guides/server/self-host/install"},
    {:exact, "/cloud/on-premise/metrics", "/guides/server/self-host/telemetry"},

    # Examples and project description references
    {:exact, "/guides/examples/generated-projects", "/references/examples/generated-projects"},
    {:exact, "/references/examples", "/references/examples/generated-projects"},
    {:prefix, "/reference/examples/", "/references/examples/generated-projects/"},
    {:prefix, "/guides/examples/generated-projects/", "/references/examples/generated-projects/"},
    {:exact_absolute, "/reference/project-description",
     "https://projectdescription.tuist.dev/documentation/projectdescription"},
    {:exact_absolute, "/references/project-description",
     "https://projectdescription.tuist.dev/documentation/projectdescription"},
    {:prefix_discard_absolute, "/reference/project-description/",
     "https://projectdescription.tuist.dev/documentation/projectdescription"},
    {:prefix_discard_absolute, "/references/project-description/",
     "https://projectdescription.tuist.dev/documentation/projectdescription"},

    # VitePress docs reorganizations
    {:exact, "/guides/develop/workflows", "/guides/integrations/continuous-integration"},
    {:exact, "/guides/dashboard/on-premise/install", "/guides/server/self-host/install"},
    {:exact, "/guides/dashboard/on-premise/metrics", "/guides/server/self-host/telemetry"},
    {:exact, "/guides/start/new-project", "/guides/features/projects/adoption/new-project"},
    {:exact, "/guides/start/swift-package", "/guides/features/projects/adoption/swift-package"},
    {:exact, "/guides/start/migrate/xcode-project", "/guides/features/projects/adoption/migrate/xcode-project"},
    {:exact, "/guides/start/migrate/swift-package", "/guides/features/projects/adoption/migrate/swift-package"},
    {:exact, "/guides/start/migrate/xcodegen-project", "/guides/features/projects/adoption/migrate/xcodegen-project"},
    {:exact, "/guides/start/migrate/bazel-project", "/guides/features/projects/adoption/migrate/bazel-project"},
    {:exact, "/guides/develop/build/cache", "/guides/features/cache"},
    {:exact, "/guides/develop/build/registry", "/guides/features/registry"},
    {:exact, "/guides/develop/test/smart-runner", "/guides/features/selective-testing"},
    {:exact, "/guides/develop/test/selective-testing", "/guides/features/selective-testing"},
    {:exact, "/guides/develop/inspect/implicit-dependencies", "/guides/features/projects/inspect/implicit-dependencies"},
    {:exact, "/guides/develop/automate/continuous-integration", "/guides/integrations/continuous-integration"},
    {:exact, "/guides/develop/automate/workflows", "/guides/integrations/continuous-integration"},
    {:exact, "/guides/automate/workflows", "/guides/integrations/continuous-integration"},
    {:exact, "/guides/develop/selective-testing/xcodebuild", "/guides/features/selective-testing"},
    {:exact, "/guides/features/mcp", "/guides/features/agentic-coding/mcp"},
    {:exact, "/guides/features/agentic-building/mcp", "/guides/features/agentic-coding/mcp"},
    {:exact, "/guides/environments/continuous-integration", "/guides/integrations/continuous-integration"},
    {:exact, "/guides/environments/automate/continuous-integration", "/guides/integrations/continuous-integration"},
    {:prefix, "/guides/automate/", "/guides/environments/"},
    {:prefix, "/guides/develop/", "/guides/features/"},
    {:exact, "/server/introduction/accounts-and-projects", "/guides/server/accounts-and-projects"},
    {:exact, "/server/introduction/authentication", "/guides/server/authentication"},
    {:exact, "/server/introduction/integrations", "/guides/integrations/gitforge/github"},
    {:exact, "/server/on-premise/install", "/guides/server/self-host/install"},
    {:exact, "/server/on-premise/metrics", "/guides/server/self-host/telemetry"},
    {:exact, "/guides/server/install", "/guides/server/self-host/install"},
    {:exact, "/guides/server/metrics", "/guides/server/self-host/telemetry"},
    {:exact, "/server", "/guides/server/accounts-and-projects"},
    {:exact, "/guides/quick-start/install-tuist", "/guides/install-tuist"},
    {:exact, "/tutorials/xcode/install-tuist", "/guides/install-tuist"},
    {:exact, "/tutorials/install-tuist", "/guides/install-tuist"},
    {:exact, "/guides/quick-start/get-started", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/guides/quick-start/add-dependencies", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/guides/quick-start/gather-insights", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/xcode/get-started", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/xcode/add-dependencies", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/tutorials/xcode/gather-insights", "/tutorials/xcode/create-a-generated-project"},
    {:exact, "/guides/features/insights", "/guides/features/build-insights"},
    {:exact, "/guides/features/insights/xcode-cache", "/guides/features/build-insights/xcode"},
    {:exact, "/guides/features/insights/gradle-cache", "/guides/features/build-insights/gradle"},
    {:exact, "/cli/logging", "/cli/debugging"}
  ]

  def rules, do: @rules

  def legacy_host_path(request_path) when is_binary(request_path) do
    case normalize_legacy_segments(request_path) do
      [] ->
        "/en/docs"

      ["docs" | rest] ->
        build_legacy_docs_host_path(rest)

      [locale | rest] when locale in @supported_locales ->
        build_docs_path(locale, "/" <> Enum.join(rest, "/"), "")

      [locale | rest] when locale in @legacy_english_fallback_locales ->
        build_docs_path("en", "/" <> Enum.join(rest, "/"), "")

      segments ->
        build_docs_path("en", "/" <> Enum.join(segments, "/"), "")
    end
  end

  def resolve(request_path, query_string \\ "")

  def resolve(request_path, query_string) when is_binary(request_path) do
    case Regex.named_captures(@docs_path_regex, request_path) do
      %{"locale" => locale, "rest" => rest} ->
        rest = rest || ""

        case resolve_logical_path(rest, MapSet.new()) do
          :none ->
            :none

          {:logical, new_rest} ->
            {:ok, build_docs_path(locale, new_rest, query_string)}

          {:absolute, new_path} ->
            {:ok, append_query_string(new_path, query_string)}
        end

      nil ->
        :none
    end
  end

  defp resolve_logical_path(path, seen) do
    if MapSet.member?(seen, path) do
      {:logical, path}
    else
      case apply_rules(path) do
        :none ->
          if MapSet.size(seen) == 0, do: :none, else: {:logical, path}

        {:logical, new_path} ->
          resolve_logical_path(new_path, MapSet.put(seen, path))

        {:absolute, new_path} ->
          {:absolute, new_path}
      end
    end
  end

  defp apply_rules(path) do
    Enum.find_value(@rules, :none, &apply_rule(path, &1))
  end

  defp apply_rule(path, {:exact, from, to}) when path == from, do: {:logical, to}
  defp apply_rule(path, {:exact_absolute, from, to}) when path == from, do: {:absolute, to}

  defp apply_rule(path, {:prefix, from, to}) do
    case path do
      ^from <> suffix -> {:logical, to <> suffix}
      _ -> false
    end
  end

  defp apply_rule(path, {:prefix_discard, from, to}) do
    case path do
      ^from <> _suffix -> {:logical, to}
      _ -> false
    end
  end

  defp apply_rule(path, {:prefix_discard_absolute, from, to}) do
    case path do
      ^from <> _suffix -> {:absolute, to}
      _ -> false
    end
  end

  defp apply_rule(_path, _rule), do: false

  defp build_docs_path(locale, rest, query_string) do
    locale
    |> Paths.public_path(rest)
    |> append_query_string(query_string)
  end

  defp build_legacy_docs_host_path([]), do: "/en/docs"

  defp build_legacy_docs_host_path([locale | rest]) when locale in @supported_locales do
    build_docs_path(locale, "/" <> Enum.join(rest, "/"), "")
  end

  defp build_legacy_docs_host_path([locale | rest]) when locale in @legacy_english_fallback_locales do
    build_docs_path("en", "/" <> Enum.join(rest, "/"), "")
  end

  defp build_legacy_docs_host_path(segments) do
    build_docs_path("en", "/" <> Enum.join(segments, "/"), "")
  end

  defp normalize_legacy_segments(request_path) do
    request_path
    |> String.trim()
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> drop_trailing_index()
  end

  defp drop_trailing_index(segments) do
    case Enum.reverse(segments) do
      ["index" | rest] -> Enum.reverse(rest)
      _ -> segments
    end
  end

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
