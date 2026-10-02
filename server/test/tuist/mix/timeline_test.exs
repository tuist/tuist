defmodule Tuist.Mix.TimelineTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.Mix
  alias Tuist.Mix.Timeline
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @start ~U[2026-09-09 10:00:00.000000Z]

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)
    %{user: user, project: project}
  end

  defp build(%{user: user, project: project}, attrs) do
    id = UUIDv7.generate()

    {:ok, ^id} =
      Mix.create_build(
        Map.merge(
          %{
            id: id,
            project_id: project.id,
            account_id: user.account.id,
            duration_ms: 2_000,
            status: "success",
            started_at: @start
          },
          attrs
        )
      )

    for buffer <- [
          Mix.Build.Buffer,
          Mix.Diagnostic.Buffer,
          Mix.CompiledFile.Buffer,
          Mix.Step.Buffer,
          BuildMachineMetric.Buffer
        ],
        do: buffer.flush()

    {:ok, build} = Mix.get_build(id, project_id: project.id)
    build
  end

  defp sample(offset_ms) do
    %{
      timestamp: DateTime.to_unix(@start, :millisecond) / 1000 + offset_ms / 1000,
      cpu_usage_percent: 50.0,
      memory_used_bytes: 1,
      memory_total_bytes: 2
    }
  end

  test "shows only the stretches a file was being compiled, leaving out the time it waited", context do
    build =
      build(context, %{
        files: [
          %{path: "lib/macros.ex", start_offset_ms: 10, compile_duration_ms: 1_500, modules: ["Demo.Macros"]},
          %{
            path: "lib/greeter.ex",
            start_offset_ms: 20,
            compile_duration_ms: 70,
            wait_duration_ms: 1_480,
            modules: ["Demo.Greeter"],
            waits: [
              %{module: "Demo.Macros", path: "lib/macros.ex", kind: "module", duration_ms: 1_480, start_offset_ms: 30}
            ]
          }
        ]
      })

    timeline = Timeline.load(build)

    assert [
             %{target: "lib/macros.ex", title: "Demo.Macros", category: "compile", start_ms: 10, duration_ms: 1_500},
             %{target: "lib/greeter.ex", title: "Demo.Greeter", category: "compile", start_ms: 20, duration_ms: 10},
             %{target: "lib/greeter.ex", title: "Demo.Greeter", category: "compile", start_ms: 1_510, duration_ms: 60}
           ] = timeline.events

    assert timeline.total_count == 3
    assert timeline.duration == 2_000
    assert timeline.local_navigation
    refute timeline.logs_available
    assert Timeline.available?(build)
  end

  test "includes the other work the compiler reported, by kind", context do
    build =
      build(context, %{
        files: [%{path: "lib/greeter.ex", start_offset_ms: 0, compile_duration_ms: 100, modules: ["Demo.Greeter"]}],
        steps: [
          %{category: "write", title: "Writing modules to disk", start_offset_ms: 100, duration_ms: 20},
          %{
            category: "type_check",
            title: "Type checking Demo.Greeter",
            path: "lib/greeter.ex",
            start_offset_ms: 120,
            duration_ms: 30
          },
          %{category: "compiler", title: "mix compile.app", start_offset_ms: 150, duration_ms: 12},
          %{category: "linking", title: "Something newer clients report", start_offset_ms: 162, duration_ms: 5}
        ]
      })

    assert [
             %{category: "compile", target: "lib/greeter.ex"},
             %{category: "write", title: "Writing modules to disk", target: "", start_ms: 100, duration_ms: 20},
             %{category: "type_check", title: "Type checking Demo.Greeter", target: "lib/greeter.ex", start_ms: 120},
             %{category: "compiler", title: "mix compile.app", start_ms: 150, duration_ms: 12},
             %{category: "other", title: "Something newer clients report"}
           ] = Timeline.load(build).events
  end

  test "is available from reported steps alone", context do
    build =
      build(context, %{
        steps: [%{category: "write", title: "Writing modules to disk", start_offset_ms: 100, duration_ms: 20}]
      })

    assert Timeline.available?(build)
  end

  test "keeps a wait it cannot place inside the file's span instead of guessing where it happened", context do
    build =
      build(context, %{
        files: [
          %{
            path: "lib/greeter.ex",
            start_offset_ms: 0,
            compile_duration_ms: 100,
            wait_duration_ms: 50,
            modules: [],
            waits: [%{module: "Ecto.Changeset", kind: "struct", duration_ms: 50}]
          }
        ]
      })

    assert [%{title: "greeter.ex", category: "compile", start_ms: 0, duration_ms: 150}] = Timeline.load(build).events
  end

  test "marks the files that failed to compile", context do
    build =
      build(context, %{
        status: "failure",
        diagnostics: [%{severity: "error", file: "lib/broken.ex", message: "undefined function"}],
        files: [
          %{path: "lib/broken.ex", start_offset_ms: 0, compile_duration_ms: 40, modules: []},
          %{path: "lib/fine.ex", start_offset_ms: 0, compile_duration_ms: 40, modules: ["Fine"]}
        ]
      })

    assert %{"lib/broken.ex" => "failure", "lib/fine.ex" => "success"} =
             Map.new(Timeline.load(build).events, &{&1.target, &1.status})
  end

  test "is unavailable for a build whose files have no recorded start", context do
    build = build(context, %{files: [%{path: "lib/a.ex", compile_duration_ms: 40, modules: ["A"]}]})

    refute Timeline.available?(build)
    assert Timeline.load(build).events == []
  end

  test "aligns machine samples with the build start and loads them apart from the files", context do
    build =
      build(context, %{
        files: [%{path: "lib/a.ex", start_offset_ms: 0, compile_duration_ms: 40, modules: ["A"]}],
        machine_metrics: [sample(-500), sample(250), sample(2_500)]
      })

    assert [-500.0, 250.0, 2_500.0] = Enum.map(Timeline.load(build).machine_metrics, & &1.offset_ms)

    bootstrap = Timeline.bootstrap(build)
    assert length(bootstrap.machine_metrics) == 3
    assert bootstrap.duration == 2_500
    refute Map.has_key?(bootstrap, :events)

    metadata = Timeline.load(build, include_metrics: false)
    assert metadata.has_metrics
    assert metadata.duration == 2_500
    refute Map.has_key?(metadata, :machine_metrics)
  end
end
