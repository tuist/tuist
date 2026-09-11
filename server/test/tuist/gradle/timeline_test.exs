defmodule Tuist.Gradle.TimelineTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Builds.RecordedSteps
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle
  alias Tuist.Gradle.ConfigurationOperation
  alias Tuist.Gradle.Timeline
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.GradleFixtures

  @start ~U[2026-09-09 10:00:00.123000Z]

  test "availability accepts aligned samples but not samples entirely before the build" do
    for {offset, available} <- [{-1, false}, {1, true}] do
      id =
        GradleFixtures.build_fixture(
          started_at: @start,
          machine_metrics: [
            metric(DateTime.to_unix(@start, :microsecond) / 1_000_000 + offset)
          ]
        )

      {:ok, build} = Gradle.get_build(id)
      assert Timeline.available?(build) == available
    end
  end

  test "zero-duration task outcomes are retained in the timeline and step API" do
    outcomes = ~w(cache_hit up_to_date skipped no_source)
    tasks = Enum.map(outcomes, &Map.put(task(":#{&1}", &1, @start), :duration_ms, 0))
    id = GradleFixtures.build_fixture(started_at: @start, tasks: tasks)
    {:ok, build} = Gradle.get_build(id)
    assert Timeline.load(build).total_count == 4
    assert Timeline.available?(build)

    for outcome <- outcomes do
      assert {:ok, %{steps: [%{status: ^outcome, duration_ms: 0} = step]}} = RecordedSteps.list(build, %{status: outcome})
      assert {:ok, %{status: ^outcome, duration_ms: 0}} = RecordedSteps.get(build, step.id)
    end
  end

  test "step offsets preserve microseconds at the build boundary" do
    id =
      GradleFixtures.build_fixture(
        started_at: @start,
        tasks: [
          task(":at-start", "executed", @start),
          task(":one-microsecond", "executed", DateTime.add(@start, 1, :microsecond))
        ]
      )

    {:ok, build} = Gradle.get_build(id)

    assert {:ok, %{steps: [%{start_ms: first}, %{start_ms: second}]}} =
             RecordedSteps.list(build, %{sort_by: "start_ms"})

    assert first == 0
    assert second == 0.001
  end

  test "an empty legacy origin cannot turn later arrivals into epoch-sized offsets" do
    id = GradleFixtures.build_fixture()
    {:ok, build} = Gradle.get_build(id)
    query_before_arrival = Timeline.step_query(build)

    IngestRepo.insert_all(ConfigurationOperation, [
      %{
        id: Ecto.UUID.generate(),
        gradle_build_id: id,
        project_id: build.project_id,
        phase: "settings",
        build_path: ":",
        project_path: ":",
        started_at: DateTime.to_naive(@start),
        duration_ms: 100,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])

    assert ClickHouseRepo.all(query_before_arrival) == []
    assert {:ok, %{steps: [%{start_ms: offset}]}} = RecordedSteps.list(build, %{})
    assert offset == 0
  end

  test "loads all operations, scopes project data and aligns metrics with the reported build clock" do
    id =
      GradleFixtures.build_fixture(
        started_at: @start,
        duration_ms: 5000,
        tasks: [
          task(":app:compileKotlin", "executed", DateTime.add(@start, 1500, :millisecond)),
          task(":app:cached", "remote_hit", DateTime.add(@start, 1500, :millisecond)),
          task(":app:legacy", "failed", nil)
        ],
        configuration_operations:
          Enum.map(1..101, fn _ ->
            %{phase: "project", build_path: ":", project_path: ":app", started_at: @start, duration_ms: 1000}
          end),
        artifact_transforms: [
          %{
            transformer_name: "Jetify",
            transform_action_class: "JetifyTransform",
            artifact_name: "library.jar",
            subject_name: "library.jar",
            consumer_project_path: ":app",
            started_at: DateTime.add(@start, 500, :millisecond),
            duration_ms: 1000
          }
        ],
        machine_metrics: [metric(DateTime.to_unix(@start, :microsecond) / 1_000_000 + 1)]
      )

    {:ok, build} = Gradle.get_build(id)

    IngestRepo.insert_all(ConfigurationOperation, [
      %{
        id: Ecto.UUID.generate(),
        gradle_build_id: id,
        project_id: build.project_id + 1,
        phase: "foreign",
        build_path: ":",
        project_path: ":secret",
        started_at: DateTime.to_naive(@start),
        duration_ms: 1000,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])

    timeline = Timeline.load(build)
    bootstrap = Timeline.bootstrap(build)
    assert bootstrap.machine_metrics == timeline.machine_metrics
    assert bootstrap.time_origin == timeline.time_origin
    refute Map.has_key?(bootstrap, :events)
    assert timeline.total_count == 104
    assert timeline.duration == 5000
    assert timeline.time_origin == "build_start"
    assert [%{offset_ms: offset}] = timeline.machine_metrics
    assert_in_delta offset, 1000, 0.001
    assert %{start_ms: 1500.0, status: "remote_hit"} = Enum.find(timeline.events, &(&1.title == ":app:cached"))
    refute Enum.any?(timeline.events, &(&1.title == "foreign"))
    refute Enum.any?(timeline.events, &(&1.title == ":app:legacy"))

    assert {:ok, %{steps: [step], availability: "available"}} = RecordedSteps.list(build, %{search: "CACHED"})
    assert step.category == "task"
    assert {:ok, %{id: step_id, log: nil}} = RecordedSteps.get(build, step.id)
    assert step_id == step.id
    assert {:ok, %{steps: [], availability: "available"}} = RecordedSteps.list(build, %{search: "no match"})
    assert {:ok, %{steps: [], availability: "available"}} = RecordedSteps.list(build, %{start_ms: 1600, end_ms: 2000})
    assert {:error, :invalid_range} = RecordedSteps.list(build, %{start_ms: 10, end_ms: 10})
    assert {:error, :invalid_filters} = RecordedSteps.list(build, %{page_size: 101})
  end

  test "keeps the closest measured sample before the origin to draw across the build boundary" do
    build = %Gradle.Build{duration_ms: 1000, root_project_name: "App", started_at: @start}
    origin = DateTime.to_unix(@start, :microsecond) / 1_000_000
    samples = Enum.map([-2, -1, 0.5, 1], &metric(origin + &1))

    timeline = Timeline.normalize(build, [], [], [], samples)
    assert Enum.map(timeline.machine_metrics, & &1.offset_ms) == [-1000.0, 500.0, 1000.0]
    assert timeline.duration == 1000
    refute Timeline.normalize(build, [], [], [], [metric(origin - 1)]).has_metrics
  end

  test "legacy metric bootstrap uses the operation origin without loading step metadata" do
    id =
      GradleFixtures.build_fixture(
        tasks: [task(":compile", "executed", @start)],
        machine_metrics: [metric(DateTime.to_unix(@start, :microsecond) / 1_000_000 + 1)]
      )

    {:ok, build} = Gradle.get_build(id)
    bootstrap = Timeline.bootstrap(build)
    assert bootstrap.time_origin == "first_recorded_timestamp"
    assert bootstrap.machine_metrics == Timeline.load(build).machine_metrics
    metadata = Timeline.load(build, include_metrics: false)
    assert metadata.events == Timeline.load(build).events
    assert metadata.duration == Timeline.load(build).duration
    assert metadata.has_metrics
    refute Map.has_key?(metadata, :machine_metrics)
    assert [%{offset_ms: offset}] = bootstrap.machine_metrics
    assert_in_delta offset, 1000, 0.001
    refute Map.has_key?(bootstrap, :events)
  end

  test "legacy reports use the earliest recording, including setup before the first task" do
    build = %Gradle.Build{duration_ms: 5000, root_project_name: "App"}

    task =
      Map.merge(task(":app:compile", "failed", DateTime.add(@start, 2, :second)), %{
        id: "task",
        build_path: ":",
        task_type: "compile"
      })

    config = %{id: "config", phase: "settings", build_path: ":", project_path: ":", started_at: @start, duration_ms: 1000}
    timeline = Timeline.normalize(build, [task], [config], [], [])
    assert timeline.time_origin == "first_recorded_timestamp"
    assert [%{start_ms: first}, %{start_ms: 2000.0, status: "failure"}] = timeline.events
    assert first == 0
    assert timeline.duration == 5000
  end

  test "builds with only metrics and builds with no recordings have distinct availability" do
    build = %Gradle.Build{duration_ms: 1000, root_project_name: "App", started_at: @start}
    timeline = Timeline.normalize(build, [], [], [], [metric(DateTime.to_unix(@start, :microsecond) / 1_000_000)])
    assert timeline.has_metrics
    assert timeline.total_count == 0
    refute Timeline.normalize(build, [], [], [], []).has_metrics
  end

  defp task(path, outcome, started_at), do: %{task_path: path, outcome: outcome, started_at: started_at, duration_ms: 100}

  defp metric(timestamp),
    do: %{
      timestamp: timestamp,
      cpu_usage_percent: 42,
      memory_used_bytes: 1000,
      memory_total_bytes: 2000,
      network_bytes_in: 10,
      network_bytes_out: 20,
      disk_bytes_read: 30,
      disk_bytes_written: 40
    }
end
