defmodule Tuist.Automations.Builds.CacheKeyMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Automations.Builds.CacheKeyMonitor
  alias Tuist.Bazel.Invocation
  alias Tuist.Builds.CacheableTask.Buffer
  alias Tuist.IngestRepo
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.Run
  alias Tuist.ReapiCache.CacheEvent
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture(), cutoff: DateTime.add(DateTime.utc_now(:second), -30, :day)}
  end

  test "Gradle compares full task identity and distinct builds, not temporal flips", %{project: project, cutoff: cutoff} do
    for key <- ["a", "b", "a"] do
      gradle(project, [task(":app:compile", key)])
    end

    assert [%{unit_name: ":app:compile", first_key: "a", second_key: "b", commit_sha: "commit"} = finding] =
             CacheKeyMonitor.page(project.id, "gradle", "", cutoff)

    refute finding.first_run == finding.second_run
    assert CacheKeyMonitor.page(project.id, "gradle", finding.unit_key, cutoff) == []
  end

  test "Gradle excludes local, missing, non-cacheable, cross-commit and cross-project evidence", %{
    project: project,
    cutoff: cutoff
  } do
    gradle(project, [task(":local", "a")])
    gradle(project, [task(":local", "b")], is_ci: false)
    gradle(project, [task(":missing", "")])
    gradle(project, [task(":missing", "b")])
    gradle(project, [task(":changed", "a")])
    gradle(project, [task(":changed", "b")], git_commit_sha: "another")
    gradle(project, [task(":no-commit", "a")], git_commit_sha: "")
    gradle(project, [task(":no-commit", "b")], git_commit_sha: "")
    gradle(project, [task(":disabled", "a", "disabled")])
    gradle(project, [task(":disabled", "b", "disabled")])
    gradle(project, [task(":isolated", "a")])
    other = ProjectsFixtures.project_fixture()
    gradle(other, [task(":isolated", "b")])
    assert CacheKeyMonitor.page(project.id, "gradle", "", cutoff) == []
  end

  test "Gradle does not merge tasks in different root projects, build paths or types", %{project: project, cutoff: cutoff} do
    gradle(project, [task(":compile", "a")], root_project_name: "one")
    gradle(project, [task(":compile", "b")], root_project_name: "two")
    gradle(project, [":compile" |> task("c") |> put_in([:execution, :build_path], ":included")], root_project_name: "one")

    gradle(project, [":compile" |> task("d") |> put_in([:execution, :task_type], "OtherCompile")],
      root_project_name: "one"
    )

    assert CacheKeyMonitor.page(project.id, "gradle", "", cutoff) == []
  end

  test "ambiguous identities within one build are not cross-build inconsistencies", %{project: project, cutoff: cutoff} do
    gradle(project, [task(":compile", "a"), task(":compile", "b")])
    gradle(project, [task(":compile", "c")])
    assert CacheKeyMonitor.page(project.id, "gradle", "", cutoff) == []
  end

  test "Bazel separates actions under one target by configuration and primary output", %{project: project, cutoff: cutoff} do
    bazel(project, "first", [{"main.o", "a"}, {"other.o", "x"}, {"", "missing-a"}])
    bazel(project, "second", [{"main.o", "b"}, {"other.o", "x"}, {"", "missing-b"}])
    assert [%{first_key: "a", second_key: "b", unit_name: name}] = CacheKeyMonitor.page(project.id, "bazel", "", cutoff)
    assert name =~ "main.o"
  end

  test "Xcode modules compare project and target identity, not per-run graph IDs", %{project: project, cutoff: cutoff} do
    for key <- ["a", "b"] do
      event = CommandEventsFixtures.command_event_fixture(project_id: project.id, is_ci: true, git_commit_sha: "commit")
      graph = XcodeFixtures.xcode_graph_fixture(command_event_id: event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(name: "App", command_event_id: event.id, xcode_graph_id: graph.id)

      XcodeFixtures.xcode_target_fixture(
        name: "Core",
        binary_cache_hash: key,
        command_event_id: event.id,
        xcode_project_id: xcode_project.id
      )
    end

    assert [%{unit_name: "App/Core", first_key: "a", second_key: "b"}] =
             CacheKeyMonitor.page(project.id, "xcode_module", "", cutoff)
  end

  test "Xcode compilation skips absent and ambiguous task descriptions", %{project: project, cutoff: cutoff} do
    for key <- ["a", "b"] do
      RunsFixtures.build_fixture(
        project_id: project.id,
        is_ci: true,
        git_commit_sha: "commit",
        cacheable_tasks: [
          %{type: "swift", status: "miss", key: key, description: "Compile Core.swift"},
          %{type: "clang", status: "miss", key: key, description: nil},
          %{type: "swift", status: "miss", key: "first-#{key}", description: "Ambiguous"},
          %{type: "swift", status: "miss", key: "second-#{key}", description: "Ambiguous"}
        ]
      )
    end

    Buffer.flush()

    assert [%{unit_name: "Compile Core.swift", first_key: "a", second_key: "b"}] =
             CacheKeyMonitor.page(project.id, "xcode_compilation", "", cutoff)
  end

  test "commit batches honor distinct CI runs and the durable commit cursor", %{project: project, cutoff: cutoff} do
    gradle(project, [task(":compile", "a")], git_commit_sha: "aaaa")
    gradle(project, [task(":compile", "b")], git_commit_sha: "aaaa")
    gradle(project, [task(":compile", "c")], git_commit_sha: "bbbb")
    until = DateTime.utc_now()
    assert CacheKeyMonitor.commits(project.id, "gradle", "", cutoff, cutoff, until) == ["aaaa"]
    assert CacheKeyMonitor.commits(project.id, "gradle", "aaaa", cutoff, cutoff, until) == []
    assert CacheKeyMonitor.page(project.id, "gradle", "", cutoff, commit: "bbbb", until: until) == []
  end

  test "compilation configurations and schemes are distinct units", %{project: project, cutoff: cutoff} do
    for {configuration, key} <- [{"Debug", "a"}, {"Release", "b"}] do
      RunsFixtures.build_fixture(
        project_id: project.id,
        is_ci: true,
        git_commit_sha: "commit",
        configuration: configuration,
        cacheable_tasks: [%{type: "swift", status: "miss", key: key, description: "Compile Core.swift"}]
      )
    end

    Buffer.flush()
    assert CacheKeyMonitor.page(project.id, "xcode_compilation", "", cutoff) == []
  end

  test "module producer and consumer commands remain comparable", %{project: project, cutoff: cutoff} do
    for {command, key} <- [{"cache", "a"}, {"generate", "b"}] do
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          is_ci: true,
          git_commit_sha: "commit",
          name: command
        )

      graph = XcodeFixtures.xcode_graph_fixture(command_event_id: event.id)

      xcode_project =
        XcodeFixtures.xcode_project_fixture(name: "App", command_event_id: event.id, xcode_graph_id: graph.id)

      XcodeFixtures.xcode_target_fixture(
        name: "Core",
        binary_cache_hash: key,
        command_event_id: event.id,
        xcode_project_id: xcode_project.id
      )
    end

    assert [%{first_key: "a", second_key: "b"}] = CacheKeyMonitor.page(project.id, "xcode_module", "", cutoff)
  end

  test "Once compares declared actions, excluding active, dirty and local runs", %{project: project, cutoff: cutoff} do
    once(project, "a")
    once(project, "b")
    once(project, "dirty", git_dirty: true)
    once(project, "local", is_ci: false)
    once(project, "active", finalization: "active")

    assert [%{unit_name: "compile", first_key: "a", second_key: "b"}] =
             CacheKeyMonitor.page(project.id, "once", "", cutoff)
  end

  defp gradle(project, tasks, opts \\ []) do
    GradleFixtures.build_fixture(
      Keyword.merge(
        [project_id: project.id, is_ci: true, git_commit_sha: "commit", root_project_name: "App", tasks: tasks],
        opts
      )
    )
  end

  defp task(path, key, cacheability \\ "cacheable") do
    %{
      task_path: path,
      cache_key: key,
      cacheable: true,
      outcome: "executed",
      duration_ms: 100,
      execution: %{build_path: ":", task_type: "Compile", cacheability: cacheability}
    }
  end

  defp bazel(project, run_id, outputs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    IngestRepo.insert_all(Invocation, [
      %{
        id: UUIDv7.generate(),
        invocation_id: run_id,
        project_id: project.id,
        is_ci: true,
        git_commit_sha: "commit",
        status: "success",
        command: "build",
        inserted_at: now,
        started_at: now,
        finished_at: now,
        duration_ms: 100,
        exit_code: 0
      }
    ])

    for {output, key} <- outputs do
      IngestRepo.insert_all(CacheEvent, [
        %{
          id: UUIDv7.generate(),
          project_id: project.id,
          invocation_id: run_id,
          client_kind: "bazel",
          operation: "action_cache",
          outcome: "write",
          action_digest: key,
          target_label: "//:app",
          action_mnemonic: "CppCompile",
          configuration_id: "debug",
          output_path: output,
          size: 0,
          duration_ms: 0,
          duration_us: 0,
          observed_at: DateTime.utc_now(),
          inserted_at: now,
          account_handle: "",
          project_handle: "",
          cache_endpoint: ""
        }
      ])
    end
  end

  defp once(project, key, opts \\ []) do
    run =
      Run
      |> struct!(
        Keyword.merge(
          [
            project_id: project.id,
            run_id: UUIDv7.generate(),
            is_ci: true,
            git_rev: "commit",
            finalization: "finalized",
            started_at: DateTime.utc_now()
          ],
          opts
        )
      )
      |> Repo.insert!()

    Repo.insert!(%Action{
      project_id: project.id,
      once_run_id: run.id,
      run_id: run.run_id,
      target_execution_id: "app",
      capability: "build",
      identifier: "compile",
      cache_key: key,
      result: "succeeded",
      finished_at: DateTime.utc_now()
    })
  end
end
