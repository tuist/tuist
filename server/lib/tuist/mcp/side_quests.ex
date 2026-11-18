defmodule Tuist.MCP.SideQuests do
  @moduledoc """
  Side quests: Tuist capabilities a project is not using that the record an
  agent just fetched shows would help, such as a CI build on hosted machines
  that Tuist Runners could take, or a flaky test run with no quarantine.

  An agent reading a build, a test run or a project sees none of the
  dashboard's prompts that would tell a person about these, so those tools
  attach them to their result as `side_quests`. Each one is decided from data
  the tool already loaded plus at most one cheap lookup, and states the
  evidence it fired on so the agent can judge whether it applies before it
  mentions it to the user.

  They describe the caller's own account (which build systems it uses, whether
  it runs jobs on Tuist Runners), so they are only computed for members of the
  project's account, never for someone reading a public project. Tuist
  operators reading through Atlas get none either: the tips are written for the
  customer.
  """

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Authorization
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Tests.RunSelections

  @docs_url "https://tuist.dev/en/docs/guides"

  @runner_providers %{
    "github" => %{name: "GitHub Actions", docs: "github-actions"},
    "bitrise" => %{name: "Bitrise", docs: "bitrise"},
    "gitlab" => %{name: "GitLab CI", docs: "gitlab-ci"},
    "buildkite" => %{name: "Buildkite", docs: "buildkite"}
  }

  @build_system_names [
    xcode: "Xcode",
    gradle: "Gradle",
    bazel: "Bazel",
    once: "Once",
    mix: "Elixir",
    cargo: "Rust"
  ]

  # Once is left out of the suggestions while it is in canary.
  @suggested_build_systems [
    xcode: "`*.xcodeproj`, `*.xcworkspace` or `Package.swift`",
    gradle: "`settings.gradle(.kts)` or `build.gradle(.kts)`",
    bazel: "`MODULE.bazel` or `WORKSPACE`",
    mix: "`mix.exs`",
    cargo: "`Cargo.toml`; its cache is experimental"
  ]

  # Once has no Automations settings and its client does not enforce
  # quarantine, so it gets no quarantine suggestion.
  @flaky_test_docs %{
    xcode: "xcode",
    gradle: "gradle",
    bazel: "bazel",
    mix: "elixir",
    cargo: "rust"
  }

  # Bazel shards with its own `shard_count`, so it has no Tuist sharding guide.
  @test_sharding_docs %{
    xcode: "xcode",
    gradle: "gradle",
    mix: "elixir",
    cargo: "rust",
    once: "once"
  }

  # Long enough that a few parallel shards save minutes of waiting on every
  # change, not seconds.
  @slow_test_run_ms to_timeout(minute: 10)

  @doc """
  The output schema fragment for the `side_quests` field.
  """
  def schema do
    %{
      "type" => "array",
      "description" =>
        "Optional improvements to how this project uses Tuist, suggested from this record. They are not part of " <>
          "the answer: finish what the user asked first, then mention the ones that apply in a sentence each and " <>
          "offer to do them. Never act on one without the user's agreement.",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string"},
          "tip" => %{"type" => "string"},
          "docs" => %{"type" => "string"}
        },
        "required" => ["id", "tip", "docs"],
        "additionalProperties" => false
      }
    }
  end

  def put_for_xcode_build(payload, assigns, project, build) do
    put(payload, assigns, project, fn ->
      [
        xcode_compilation_cache(build),
        tuist_runners(project, build),
        pull_request_comments(project, build)
      ]
    end)
  end

  def put_for_test_run(payload, assigns, project, run, flaky_test_count) do
    put(payload, assigns, project, fn ->
      [
        flaky_test_quarantine(project, flaky_test_count),
        test_sharding(project, run),
        tuist_runners(project, run),
        pull_request_comments(project, run)
      ]
    end)
  end

  def put_for_gradle_build(payload, assigns, project, build, cache_aggregates) do
    put(payload, assigns, project, fn -> [gradle_build_cache(build, cache_aggregates)] end)
  end

  def put_for_project(payload, assigns, project) do
    put(payload, assigns, project, fn -> [other_build_systems(project)] end)
  end

  defp put(payload, assigns, %Project{} = project, quests_fun) do
    with nil <- assigns[:atlas_operator],
         true <- Authorization.authorize_request(assigns, :read, project.account, :projects),
         [_ | _] = quests <- Enum.reject(quests_fun.(), &is_nil/1) do
      Map.put(payload, :side_quests, quests)
    else
      _ -> payload
    end
  end

  # Tools under test sometimes stub the project with a bare map. Without the
  # project's account there is nothing to suggest.
  defp put(payload, _assigns, _project, _quests_fun), do: payload

  # Xcode reports one cacheable task per compile job it ran through the
  # compilation cache, so a clean build with none never asked a cache for
  # anything. An incremental build with nothing to compile has none either,
  # and a build still processing reports 0 before its counts arrive.
  defp xcode_compilation_cache(build) do
    if to_string(Map.get(build, :status)) in ["success", "failure"] and Map.get(build, :category) == "clean" and
         Map.get(build, :cacheable_tasks_count) == 0 and xcode_major_version(build) >= 26 do
      %{
        id: "xcode_compilation_cache",
        tip:
          "This clean build ran Xcode #{build.xcode_version} with no cacheable compilation tasks, so it compiled " <>
            "everything locally instead of reusing compilation results from the Tuist cache. Running " <>
            "`tuist setup cache` and adding the build settings it prints lets this machine, CI and teammates " <>
            "share compiled outputs.",
        docs: "#{@docs_url}/features/cache/xcode-cache"
      }
    end
  end

  # Cacheability is reported per task even when Gradle's build cache is off,
  # but Gradle only computes a task's cache key while caching is on. A build
  # that executed cacheable tasks without a single key never consulted the
  # cache, unlike a read-only build whose lookups all missed. Plugins older
  # than key reporting send none, so requiring no hits keeps out their builds
  # whose cache worked.
  defp gradle_build_cache(build, cache_aggregates) do
    if build.cacheable_tasks_count > 0 and build.tasks_executed_count > 0 and build.tasks_cache_hit_count == 0 and
         cache_aggregates.cache_consulted_tasks == 0 do
      %{
        id: "gradle_build_cache",
        tip:
          "This build executed cacheable tasks without Gradle's build cache computing a key for any of them, so " <>
            "the build cache was off and no task output could come from the Tuist cache. Setting " <>
            "`org.gradle.caching=true` in `gradle.properties` turns it on; the Tuist Gradle plugin then serves " <>
            "it remotely.",
        docs: "#{@docs_url}/features/cache/gradle-cache"
      }
    end
  end

  defp flaky_test_quarantine(project, flaky_test_count) do
    with true <- flaky_test_count > 0,
         {:ok, docs} <- Map.fetch(@flaky_test_docs, project.build_system),
         false <- quarantine_automation?(project) do
      %{
        id: "flaky_test_quarantine",
        tip:
          "#{flaky_test_count} flaky #{pluralize(flaky_test_count, "test", "tests")} ran here, and no automation " <>
            "in this project quarantines flaky tests, so unless someone quarantines them by hand they can keep " <>
            "failing CI. An automation under Settings → Automations can mute or skip a test once it crosses a " <>
            "flakiness threshold and release it when it recovers.",
        docs: "#{@docs_url}/features/test-insights/flaky-tests/#{docs}"
      }
    else
      _ -> nil
    end
  end

  defp quarantine_automation?(project) do
    project.id
    |> Automations.list_alerts()
    |> Enum.any?(fn alert ->
      alert.enabled and
        Enum.any?(alert.trigger_actions, &(&1["type"] == "change_state" and &1["state"] in ["muted", "skipped"]))
    end)
  end

  defp test_sharding(project, run) do
    with true <- Map.get(run, :is_ci) == true,
         nil <- Map.get(run, :shard_plan_id),
         duration when is_integer(duration) and duration >= @slow_test_run_ms <- Map.get(run, :duration),
         {:ok, docs} <- Map.fetch(@test_sharding_docs, project.build_system) do
      selection =
        case RunSelections.get_run(project.id, run.id, run.ran_at) do
          %{avoided_tests: avoided, scope_tests: scope} when avoided > 0 ->
            " even though selective testing already skipped #{avoided} of its #{scope} tests"

          _ ->
            ""
        end

      %{
        id: "test_sharding",
        tip:
          "This CI test run took #{div(duration, to_timeout(minute: 1))} minutes on a single job#{selection}. " <>
            "Test sharding splits the tests across parallel CI jobs, balanced by their recorded durations, so the " <>
            "run finishes in about the time of its slowest shard. It shortens the wait, not the total machine time.",
        docs: "#{@docs_url}/features/test-sharding/#{docs}"
      }
    else
      _ -> nil
    end
  end

  # Runners are a managed fleet, so self-hosted servers have none to offer.
  # An account that has already run a job on them knows they exist.
  defp tuist_runners(project, run) do
    with true <- Environment.tuist_hosted?(),
         true <- Map.get(run, :is_ci) == true,
         %{name: provider, docs: docs} <- Map.get(@runner_providers, ci_provider(run)),
         false <- WorkflowJobs.any_for_account?(project.account.id) do
      profile = if project.build_system == :xcode, do: "tuist-macos", else: "tuist-linux"

      access =
        if FeatureFlags.runners_enabled?(project.account),
          do: "Runners are enabled for this account; in #{provider}, #{switch_instructions(provider, profile)}.",
          else:
            "Runners are invite-only for now, but the Tuist team gives teams access to try them: the user can " <>
              "ask at contact@tuist.dev or in the community Slack (https://slack.tuist.dev)."

      %{
        id: "tuist_runners",
        tip:
          "This CI run used #{provider} machines, and this account has not run jobs on Tuist Runners. Tuist " <>
            "Runners run the same #{provider} jobs on machines next to the Tuist cache, so cache downloads and " <>
            "uploads stay on a private network instead of crossing the internet. #{access} Moving one " <>
            "representative job and comparing its duration with this run shows whether it is faster.",
        docs: "#{@docs_url}/features/runners/ci-providers/#{docs}"
      }
    else
      _ -> nil
    end
  end

  defp switch_instructions("GitHub Actions", profile), do: "set the job's `runs-on` to `#{profile}`"

  defp switch_instructions("Bitrise", profile),
    do: "pair a runner pool with the `#{profile}` profile and select that pool under Stacks & Machines"

  defp switch_instructions("GitLab CI", profile), do: "connect the runner and add `#{profile}` to the job's `tags`"
  defp switch_instructions("Buildkite", profile), do: "set the step's `agents` queue to `#{profile}`"

  defp pull_request_comments(project, run) do
    if ci_provider(run) == "github" and is_nil(Repo.preload(project, :vcs_connection).vcs_connection) do
      %{
        id: "pull_request_comments",
        tip:
          "This run came from GitHub Actions, but the project is not connected to its GitHub repository, so " <>
            "Tuist cannot comment build and test results on pull requests or run bundle checks. The " <>
            "`connect_project_repository` tool links it once the Tuist GitHub App is installed on the repository.",
        docs: "#{@docs_url}/integrations/gitforge/github"
      }
    end
  end

  # Project-level, so it rides on `get_project`, which an agent reads about
  # once per session, rather than on every build and test run.
  defp other_build_systems(project) do
    used =
      Repo.all(from(p in Project, where: p.account_id == ^project.account_id, distinct: true, select: p.build_system))

    case Enum.reject(@suggested_build_systems, fn {build_system, _} -> build_system in used end) do
      [] ->
        nil

      unused ->
        %{
          id: "other_build_systems",
          tip:
            "This account only uses Tuist with #{used_names(used)} " <>
              "projects. Tuist also caches and analyzes builds and tests for " <>
              Enum.map_join(unused, ", ", fn {build_system, files} ->
                "#{@build_system_names[build_system]} (#{files})"
              end) <>
              ". If this project's repository contains one of those files, or the user also works on such a " <>
              "project, Tuist can cover it too: `get_gradle_integration_guide` and `get_bazel_integration_guide` " <>
              "walk through Gradle and Bazel setups.",
          docs: "#{@docs_url}/get-started"
        }
    end
  end

  defp used_names(used) do
    case for({build_system, name} <- @build_system_names, build_system in used, do: name) do
      [name] -> name
      names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)
    end
  end

  defp ci_provider(run) do
    case Map.get(run, :ci_provider) do
      provider when is_atom(provider) and not is_nil(provider) -> Atom.to_string(provider)
      provider -> provider
    end
  end

  defp xcode_major_version(build) do
    with version when is_binary(version) <- Map.get(build, :xcode_version),
         {major, _} <- Integer.parse(version) do
      major
    else
      _ -> 0
    end
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
