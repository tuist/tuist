defmodule Tuist.Runs.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias Tuist.Runs.Analytics

  describe "builds_duration_analytics/2" do
    test "returns duration analytics for the last three days" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        inserted_at: ~U[2024-04-29 10:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-27 10:00:00Z]
      )

      # When
      got =
        Analytics.builds_duration_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1500.0, 1500.0]
      assert got.trend == -25.0
      assert got.total_average_duration == 1500
    end
  end

  describe "builds_analytics/2" do
    test "returns builds analytics for the last three days" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        inserted_at: ~U[2024-04-29 10:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-27 10:00:00Z]
      )

      # When
      got =
        Analytics.builds_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      assert got.values == [0, 1, 2]
      assert got.dates == ["Apr 28", "Apr 29", "Apr 30"]
      assert got.trend == 200
      assert got.count == 3
    end
  end

  describe "runs_duration_analytics/4" do
    test "returns duration analytics for the last three days" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-27 10:00:00]
      )

      # When
      got =
        Analytics.runs_duration_analytics("generate",
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1500.0, 1500.0]
      assert got.trend == -25.0
      assert got.total_average_duration == 1500
    end

    test "returns duration analytics for user runs only" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 10:00:00],
        is_ci: false
      )

      # When
      got =
        Analytics.runs_duration_analytics("generate",
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          is_ci: false
        )

      # Then
      assert got.values == [0, 1500.0, 2000.0]
      assert got.trend == 0.0
      assert got.total_average_duration == 1750.0
    end

    test "returns runs analytics for the last 3 days" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-29 01:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-27 01:00:00]
      )

      # When
      got =
        Analytics.runs_analytics(project.id, "generate",
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1, 2]
      assert got.dates == ["Apr 28", "Apr 29", "Apr 30"]
      assert got.trend == 200
      assert got.count == 3
    end

    test "returns runs analytics for the last year" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 2000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-02-29 01:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2023-03-27 01:00:00]
      )

      # When
      got =
        Analytics.runs_analytics(project.id, "generate",
          start_date: Date.add(DateTime.utc_now(), -365)
        )

      # Then
      assert got.values == [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2]

      assert got.dates == [
               "May 2023",
               "Jun 2023",
               "Jul 2023",
               "Aug 2023",
               "Sep 2023",
               "Oct 2023",
               "Nov 2023",
               "Dec 2023",
               "Jan 2024",
               "Feb 2024",
               "Mar 2024",
               "Apr 2024"
             ]

      assert got.trend == 200
      assert got.count == 3
    end
  end

  describe "cache_hit_rate_analytics/4" do
    test "returns cache hit rates for the last three days" do
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          created_at: ~N[2024-04-30 03:00:00]
        )

      xcode_graph = XcodeFixtures.xcode_graph_fixture(command_event_id: command_event.id)
      xcode_project_one = XcodeFixtures.xcode_project_fixture(xcode_graph_id: xcode_graph.id)

      XcodeFixtures.xcode_target_fixture(
        xcode_project_id: xcode_project_one.id,
        name: "A",
        binary_cache_hit: :local,
        binary_cache_hash: "hash-a"
      )

      XcodeFixtures.xcode_target_fixture(
        xcode_project_id: xcode_project_one.id,
        name: "B",
        binary_cache_hit: :remote,
        binary_cache_hash: "hash-b"
      )

      XcodeFixtures.xcode_target_fixture(
        xcode_project_id: xcode_project_one.id,
        name: "C",
        binary_cache_hit: :miss,
        binary_cache_hash: "hash-c"
      )

      XcodeFixtures.xcode_target_fixture(
        xcode_project_id: xcode_project_one.id,
        name: "D",
        binary_cache_hit: :miss,
        binary_cache_hash: "hash-d"
      )

      # When
      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.cache_hit_rate == 0.5
    end

    test "returns cache hit rates for the last three days with legacy data" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["E", "F"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["B"],
        created_at: ~N[2024-04-27 03:00:00]
      )

      # When
      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.cache_hit_rate == 0.5
    end

    test "returns cache hit rates for the last three days for ci only" do
      # Given
      DateTime
      |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B", "C"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["B"],
        created_at: ~N[2024-04-29 03:00:00],
        is_ci: true
      )

      # When
      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now()),
          is_ci: true
        )

      # Then
      assert got.values == [0, 0.5, 0.5]
      assert got.cache_hit_rate == 0.5
    end
  end

  describe "trend/2" do
    test "returns a trend when current_value is smaller" do
      # Given / When
      got = Analytics.trend(previous_value: 20.0, current_value: 10.0)

      # Then
      assert got == -50.0
    end

    test "returns a trend when current_value is bigger" do
      # Given / When
      got = Analytics.trend(previous_value: 10.0, current_value: 20.0)

      # Then
      assert got == 100.0
    end

    test "returns 0 for a trend if previous value is 0" do
      # Given / When
      got = Analytics.trend(previous_value: 0, current_value: 20.0)

      # Then
      assert got == 0
    end

    test "returns 0 for a trend if both values are 0" do
      # Given / When
      got = Analytics.trend(previous_value: 0.0, current_value: 0)

      # Then
      assert got == 0
    end
  end
end
