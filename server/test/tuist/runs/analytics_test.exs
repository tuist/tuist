defmodule Tuist.Runs.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Runs.Analytics
  alias Tuist.Runs.TestCaseRun
  alias Tuist.Xcode.XcodeGraph
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "build_duration_analytics_by_category/3" do
    test "returns duration analytics grouped by xcode_version" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        xcode_version: "14.3.1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        xcode_version: "14.3.1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        xcode_version: "15.0.0",
        inserted_at: ~U[2024-04-29 10:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        xcode_version: "13.2.1",
        inserted_at: ~U[2024-04-27 10:00:00Z]
      )

      # When
      got =
        Analytics.build_duration_analytics_by_category(
          project.id,
          :xcode_version,
          start_date: Date.add(DateTime.utc_now(), -30)
        )

      # Then
      assert Enum.sort_by(got, & &1.category) == [
               %{value: 2000.0, category: "13.2.1"},
               %{value: 1500.0, category: "14.3.1"},
               %{value: 1500.0, category: "15.0.0"}
             ]
    end

    test "returns duration analytics grouped by model_identifier" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        model_identifier: "MacBookPro18,2",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        model_identifier: "MacBookPro18,2",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        model_identifier: "Mac14,15",
        inserted_at: ~U[2024-04-29 10:00:00Z]
      )

      # When
      got =
        Analytics.build_duration_analytics_by_category(
          project.id,
          :model_identifier,
          start_date: Date.add(DateTime.utc_now(), -30)
        )

      # Then
      assert Enum.sort_by(got, & &1.category) == [
               %{value: 1500.0, category: "Mac14,15"},
               %{value: 1500.0, category: "MacBookPro18,2"}
             ]
    end

    test "returns duration analytics grouped by macos_version" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        macos_version: "13.5.1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        macos_version: "13.5.1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        macos_version: "14.0.0",
        inserted_at: ~U[2024-04-29 10:00:00Z]
      )

      # When
      got =
        Analytics.build_duration_analytics_by_category(
          project.id,
          :macos_version,
          start_date: Date.add(DateTime.utc_now(), -30)
        )

      # Then
      assert Enum.sort_by(got, & &1.category) == [
               %{value: 1500.0, category: "13.5.1"},
               %{value: 1500.0, category: "14.0.0"}
             ]
    end
  end

  describe "builds_duration_analytics/2" do
    test "returns duration analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        Analytics.build_duration_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      # Then
      assert got.values == [0, 1500.0, 1500.0]
      assert got.trend == -25.0
      assert got.total_average_duration == 1500
    end

    test "returns duration analytics filtered by configuration" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 3000,
        configuration: "Debug",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        configuration: "Debug",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 5000,
        configuration: "Release",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      # When
      got =
        Analytics.build_duration_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          configuration: "Debug"
        )

      # Then
      assert got.values == [0, 0, 2000.0]
      assert got.total_average_duration == 2000
    end
  end

  describe "build_percentile_durations/2" do
    test "returns p90 duration analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1_000_000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 4000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
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
        Analytics.build_percentile_durations(
          project.id,
          0.5,
          start_date: ~D[2024-04-28]
        )

      # Then
      assert got.values == [0, 1500.0, 3000.0]
      # P50 of [1500, 2000, 2000, 4000, 1_000_000] = 2000
      assert got.total_percentile_duration == 2000.0
    end

    test "returns trend comparing current period percentile to previous period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Previous period (2024-04-25 to 2024-04-27): builds with p50 of 1000
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 500,
        inserted_at: ~U[2024-04-25 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        inserted_at: ~U[2024-04-26 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1500,
        inserted_at: ~U[2024-04-27 03:00:00Z]
      )

      # Current period (2024-04-28 to 2024-04-30)
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 3000,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      # When
      got =
        Analytics.build_percentile_durations(
          project.id,
          0.5,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      # Then
      # Trend from 1000 to 2000 = +100%
      assert got.trend == 100.0
      assert got.values == [1000.0, 2000.0, 3000.0]
      # P50 of [1000, 2000, 3000] = 2000
      assert got.total_percentile_duration == 2000.0
    end
  end

  describe "build_analytics/2" do
    test "returns builds analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        Analytics.build_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      assert got.values == [0, 1, 2]
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.trend == 200
      assert got.count == 3
    end
  end

  describe "runs_duration_analytics/4" do
    test "returns duration analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        duration: 3000,
        created_at: ~N[2024-04-30 03:00:00]
      )

      # When
      got =
        Analytics.runs_duration_analytics("generate",
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2)
        )

      # Then
      assert got.values == [0.0, 0.0, 2000.0]
      assert got.trend == 0.0
      assert got.total_average_duration == 2000.0
    end

    test "returns duration analytics for user runs only" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        duration: 3000,
        created_at: ~N[2024-04-30 03:00:00],
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
      assert got.values == [0.0, 0.0, 2500.0]
      assert got.trend == 0.0
      assert got.total_average_duration == 2500.0
    end

    test "returns runs analytics for the last 3 days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        Analytics.runs_analytics(project.id, "generate", start_date: Date.add(DateTime.utc_now(), -2))

      # Then
      assert got.values == [0, 1, 2]
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.trend == 200
      assert got.count == 3
    end

    test "returns runs analytics for the last year" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
        Analytics.runs_analytics(project.id, "generate", start_date: Date.add(DateTime.utc_now(), -365))

      # Then
      assert got.values == [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2]

      assert got.dates == [
               ~D[2023-05-01],
               ~D[2023-06-01],
               ~D[2023-07-01],
               ~D[2023-08-01],
               ~D[2023-09-01],
               ~D[2023-10-01],
               ~D[2023-11-01],
               ~D[2023-12-01],
               ~D[2024-01-01],
               ~D[2024-02-01],
               ~D[2024-03-01],
               ~D[2024-04-01]
             ]

      assert got.trend == 200
      assert got.count == 3
    end
  end

  describe "cache_hit_rate_analytics/4" do
    test "returns cache hit rates for Xcode builds for the last three days" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :hit_remote},
          %{key: "task3_key", type: :swift, status: :miss},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-27 04:00:00Z],
        cacheable_tasks: [
          %{key: "task5_key", type: :swift, status: :hit_local}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      assert got.cache_hit_rate == 0.5
      assert List.last(got.values) == 0.5
    end

    test "returns cache hit rates for ci builds only" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: false,
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :clang, status: :hit_remote}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task5_key", type: :swift, status: :hit_remote}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now()),
          is_ci: true
        )

      assert_in_delta got.cache_hit_rate, 0.6666, 0.01
    end
  end

  describe "selective_testing_analytics/4" do
    test "returns selective testing analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["A"],
        remote_test_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["E", "F"],
        remote_test_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B"],
        local_test_target_hits: [],
        remote_test_target_hits: ["B"],
        created_at: ~N[2024-04-27 03:00:00]
      )

      # When
      got =
        Analytics.selective_testing_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.hit_rate == 0.5
    end

    test "returns selective testing analytics for tuist xcodebuild test" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "xcodebuild",
        subcommand: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["A"],
        remote_test_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "xcodebuild",
        subcommand: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["E", "F"],
        remote_test_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "xcodebuild",
        subcommand: "test",
        test_targets: ["A", "B"],
        local_test_target_hits: [],
        remote_test_target_hits: ["B"],
        created_at: ~N[2024-04-27 03:00:00]
      )

      # When
      got =
        Analytics.selective_testing_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.hit_rate == 0.5
    end

    test "returns selective testing analytics for the last three days for ci only" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["A"],
        remote_test_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B", "C", "D"],
        local_test_target_hits: ["A", "B", "C"],
        remote_test_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "test",
        test_targets: ["A", "B"],
        local_test_target_hits: [],
        remote_test_target_hits: ["B"],
        created_at: ~N[2024-04-29 03:00:00],
        is_ci: true
      )

      # When
      got =
        Analytics.selective_testing_analytics(
          project_id: project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now()),
          is_ci: true
        )

      # Then
      assert got.values == [0, 0.5, 0.5]
      assert got.hit_rate == 0.5
    end
  end

  describe "build_success_rate_analytics/2" do
    test "returns success rate analytics for builds" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Create successful builds
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # Create failed build
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-04-29 01:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      # 3 successful out of 4 total builds
      assert got.success_rate == 0.75
      assert length(got.dates) == 3
      assert length(got.values) == 3
      # Exact success rates for each day
      assert got.values == [0.0, 0.5, 1.0]
    end

    test "returns 0% success rate when all builds fail" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.success_rate == 0.0
      assert got.values == [0.0, 0.0, 0.0]
    end

    test "returns 100% success rate when all builds succeed" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.success_rate == 1.0
      assert got.values == [0.0, 1.0, 1.0]
    end

    test "returns 0% success rate when no builds exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      assert got.success_rate == 0.0
      assert got.values == [0.0, 0.0, 0.0]
    end

    test "calculates trend correctly with previous period data" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Previous period: 1 success out of 2 builds = 50%
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        # -4 days from test date
        inserted_at: ~U[2024-04-26 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        # -4 days from test date
        inserted_at: ~U[2024-04-26 02:00:00Z]
      )

      # Current period (last 2 days): 3 success out of 4 builds = 75%
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-04-29 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-04-29 01:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -2),
          end_date: DateTime.to_date(DateTime.utc_now())
        )

      # Then
      # 3 success out of 4 builds in current period
      assert got.success_rate == 0.75
      # From 50% to 75% = +50%
      assert got.trend == 50.0
    end

    test "respects build scheme filter" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # AppOne builds: 3 success, 1 failure = 75%
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        scheme: "AppOne",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        scheme: "AppOne",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        scheme: "AppOne",
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        scheme: "AppOne",
        inserted_at: ~U[2024-04-28 02:00:00Z]
      )

      # AppTwo builds: all failures
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        scheme: "AppTwo",
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -3),
          end_date: DateTime.to_date(DateTime.utc_now()),
          scheme: "AppOne"
        )

      # Then
      assert got.success_rate == 0.75
    end

    test "respects build configuration filter" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        configuration: "Debug",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :success,
        configuration: "Debug",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        configuration: "Debug",
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        configuration: "Release",
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: :failure,
        configuration: "Release",
        inserted_at: ~U[2024-04-29 02:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_date: Date.add(DateTime.utc_now(), -3),
          end_date: DateTime.to_date(DateTime.utc_now()),
          configuration: "Debug"
        )

      # Then
      assert_in_delta got.success_rate, 0.6667, 0.0001
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

  describe "build_time_analytics/1" do
    test "returns build time analytics with real data" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)

      project = ProjectsFixtures.project_fixture()

      command_event_1 =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          created_at: ~N[2024-04-29 10:00:00],
          duration: 1500
        )

      command_event_2 =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          created_at: ~N[2024-04-28 10:00:00],
          duration: 2000
        )

      # Insert into ClickHouse XcodeGraph table
      IngestRepo.insert_all(XcodeGraph, [
        %{
          id: UUIDv7.generate(),
          name: "TestGraph1",
          command_event_id: command_event_1.id,
          binary_build_duration: 5000,
          inserted_at: NaiveDateTime.truncate(command_event_1.created_at, :second)
        },
        %{
          id: UUIDv7.generate(),
          name: "TestGraph2",
          command_event_id: command_event_2.id,
          binary_build_duration: 3000,
          inserted_at: NaiveDateTime.truncate(command_event_2.created_at, :second)
        }
      ])

      # When
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      assert got.total_time_saved == 8000
      assert got.actual_build_time == 3500
      assert got.total_build_time == 11_500
    end

    test "handles empty results correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no command events or xcode graphs exist
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      assert got.actual_build_time == 0
      assert got.total_time_saved == 0
      assert got.total_build_time == 0
    end

    test "filters by project_id correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()

      command_event_1 =
        CommandEventsFixtures.command_event_fixture(
          project_id: project1.id,
          duration: 1500,
          created_at: ~N[2024-04-29 10:00:00]
        )

      command_event_2 =
        CommandEventsFixtures.command_event_fixture(
          project_id: project2.id,
          duration: 2000,
          created_at: ~N[2024-04-28 10:00:00]
        )

      # Insert into ClickHouse XcodeGraph table
      IngestRepo.insert_all(XcodeGraph, [
        %{
          id: UUIDv7.generate(),
          name: "TestGraph1",
          command_event_id: command_event_1.id,
          binary_build_duration: 3000,
          inserted_at: NaiveDateTime.truncate(command_event_1.created_at, :second)
        },
        %{
          id: UUIDv7.generate(),
          name: "TestGraph2",
          command_event_id: command_event_2.id,
          binary_build_duration: 4000,
          inserted_at: NaiveDateTime.truncate(command_event_2.created_at, :second)
        }
      ])

      # When - query for project1 only
      got = Analytics.build_time_analytics(project_id: project1.id)

      # Then
      assert got.actual_build_time == 1500
      assert got.total_time_saved == 3000
      assert got.total_build_time == 4500
    end

    test "filters by is_ci correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      command_event_ci =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          duration: 1500,
          is_ci: true,
          created_at: ~N[2024-04-29 10:00:00]
        )

      command_event_local =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          duration: 2000,
          is_ci: false,
          created_at: ~N[2024-04-28 10:00:00]
        )

      # Insert into ClickHouse XcodeGraph table
      IngestRepo.insert_all(XcodeGraph, [
        %{
          id: UUIDv7.generate(),
          name: "TestGraphCI",
          command_event_id: command_event_ci.id,
          binary_build_duration: 3000,
          inserted_at: NaiveDateTime.truncate(command_event_ci.created_at, :second)
        },
        %{
          id: UUIDv7.generate(),
          name: "TestGraphLocal",
          command_event_id: command_event_local.id,
          binary_build_duration: 4000,
          inserted_at: NaiveDateTime.truncate(command_event_local.created_at, :second)
        }
      ])

      # When - query for CI events only
      got = Analytics.build_time_analytics(project_id: project.id, is_ci: true)

      # Then
      assert got.actual_build_time == 1500
      assert got.total_time_saved == 3000
      assert got.total_build_time == 4500
    end

    test "handles custom date range" do
      # Given
      project = ProjectsFixtures.project_fixture()

      command_event_in_range =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          created_at: ~N[2024-04-20 10:00:00],
          duration: 1000
        )

      command_event_out_of_range =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          created_at: ~N[2024-05-01 10:00:00],
          duration: 2000
        )

      IngestRepo.insert_all(XcodeGraph, [
        %{
          id: UUIDv7.generate(),
          name: "TestGraphInRange",
          command_event_id: command_event_in_range.id,
          binary_build_duration: 2000,
          inserted_at: NaiveDateTime.truncate(command_event_in_range.created_at, :second)
        },
        %{
          id: UUIDv7.generate(),
          name: "TestGraphOutOfRange",
          command_event_id: command_event_out_of_range.id,
          binary_build_duration: 3000,
          inserted_at: NaiveDateTime.truncate(command_event_out_of_range.created_at, :second)
        }
      ])

      # When - use custom date range that excludes the second event
      got =
        Analytics.build_time_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-15],
          end_date: ~D[2024-04-29]
        )

      # Then - only the first event should be included
      assert got.actual_build_time == 1000
      assert got.total_time_saved == 2000
      assert got.total_build_time == 3000
    end

    test "handles nil duration events correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      command_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          duration: nil,
          created_at: ~N[2024-04-29 10:00:00]
        )

      IngestRepo.insert_all(XcodeGraph, [
        %{
          id: UUIDv7.generate(),
          name: "TestGraphNilDuration",
          command_event_id: command_event.id,
          binary_build_duration: 1500,
          inserted_at: NaiveDateTime.truncate(command_event.created_at, :second)
        }
      ])

      # When
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      assert got.actual_build_time == 0
      assert got.total_time_saved == 1500
      assert got.total_build_time == 1500
    end
  end

  describe "build_cache_hit_rate/4" do
    test "returns Xcode build cache metrics" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :hit_remote},
          %{key: "task3_key", type: :swift, status: :miss},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task5_key", type: :swift, status: :hit_local},
          %{key: "task6_key", type: :clang, status: :miss}
        ]
      )

      got =
        Analytics.build_cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got.cacheable_tasks_count == 6
      assert got.cacheable_task_local_hits_count == 2
      assert got.cacheable_task_remote_hits_count == 1
    end

    test "returns zero counts when no builds exist" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.build_cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got.cacheable_tasks_count == 0
      assert got.cacheable_task_local_hits_count == 0
      assert got.cacheable_task_remote_hits_count == 0
    end

    test "filters by is_ci when specified" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: false,
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :clang, status: :hit_remote}
        ]
      )

      got =
        Analytics.build_cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          is_ci: true
        )

      assert got.cacheable_tasks_count == 2
      assert got.cacheable_task_local_hits_count == 1
      assert got.cacheable_task_remote_hits_count == 0
    end

    test "only includes builds with cacheable_tasks_count > 0" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 05:00:00Z],
        cacheable_tasks: []
      )

      got =
        Analytics.build_cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got.cacheable_tasks_count == 1
      assert got.cacheable_task_local_hits_count == 1
    end
  end

  describe "build_cache_hit_rates/5" do
    test "returns Xcode build cache metrics over time" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_remote},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      got =
        Analytics.build_cache_hit_rates(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          "1 day",
          []
        )

      assert length(got) == 2

      day1 = Enum.find(got, &(&1.date == "2024-04-29"))
      assert day1.cacheable_tasks == 2
      assert day1.cacheable_task_local_hits == 1
      assert day1.cacheable_task_remote_hits == 0

      day2 = Enum.find(got, &(&1.date == "2024-04-30"))
      assert day2.cacheable_tasks == 2
      assert day2.cacheable_task_local_hits == 0
      assert day2.cacheable_task_remote_hits == 1
    end

    test "returns empty list when no builds exist" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.build_cache_hit_rates(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          "1 day",
          []
        )

      assert got == []
    end

    test "groups by month when using month bucket" do
      stub(DateTime, :utc_now, fn -> ~U[2024-05-15 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-03-15 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-03-20 04:00:00Z],
        cacheable_tasks: [
          %{key: "task2_key", type: :swift, status: :hit_remote}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-10 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.build_cache_hit_rates(
          project.id,
          ~D[2024-03-01],
          ~D[2024-04-30],
          "1 month",
          []
        )

      assert length(got) == 2

      march = Enum.find(got, &(&1.date == "2024-03"))
      assert march.cacheable_tasks == 2
      assert march.cacheable_task_local_hits == 1
      assert march.cacheable_task_remote_hits == 1

      april = Enum.find(got, &(&1.date == "2024-04"))
      assert april.cacheable_tasks == 1
      assert april.cacheable_task_local_hits == 0
      assert april.cacheable_task_remote_hits == 0
    end

    test "filters by is_ci when specified" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        is_ci: false,
        cacheable_tasks: [
          %{key: "task2_key", type: :swift, status: :hit_remote}
        ]
      )

      got =
        Analytics.build_cache_hit_rates(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          "1 day",
          is_ci: true
        )

      assert length(got) == 1

      day1 = Enum.find(got, &(&1.date == "2024-04-29"))
      assert day1.cacheable_tasks == 1
      assert day1.cacheable_task_local_hits == 1
      assert day1.cacheable_task_remote_hits == 0
    end
  end

  describe "module_cache_hit_rate_analytics/1" do
    test "returns module cache hit rate analytics with correct calculations" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # Current period (2024-04-01 to 2024-04-30)
      # Create events spread across the period
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-01 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["K", "L", "M", "N", "O", "P", "Q"],
        local_cache_target_hits: ["K", "L", "M"],
        remote_cache_target_hits: ["N", "O"],
        created_at: ~N[2024-04-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["R", "S", "T", "U", "V", "W", "X"],
        local_cache_target_hits: ["R", "S", "T"],
        remote_cache_target_hits: ["U", "V"],
        created_at: ~N[2024-04-30 10:00:00]
      )

      # Previous period (2024-03-03 to 2024-04-01): 40% hit rate
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["AA", "BB", "CC", "DD", "EE"],
        local_cache_target_hits: ["AA"],
        remote_cache_target_hits: ["BB"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      # Total: 24 targets, 13 hits = 54.2%
      assert_in_delta got.avg_hit_rate, 54.2, 0.1
      assert_in_delta got.trend, 62.8, 0.1
      assert length(got.dates) == 30
      assert Enum.at(got.dates, 0) == "2024-04-01"
      assert Enum.at(got.dates, 14) == "2024-04-15"
      assert Enum.at(got.dates, 29) == "2024-04-30"
      assert_in_delta Enum.at(got.values, 0), 30.0, 0.1
      assert_in_delta Enum.at(got.values, 14), 71.4, 0.1
      assert_in_delta Enum.at(got.values, 29), 71.4, 0.1
      assert Enum.at(got.values, 1) == 0.0
      assert Enum.at(got.values, 13) == 0.0
    end

    test "returns zero hit rate when no cacheable targets exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no command events created
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "module_cache_hits_analytics/1" do
    test "returns module cache hits analytics with correct totals" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # Current period events
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-01 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["D", "E", "F", "G"],
        local_cache_target_hits: ["D", "E"],
        remote_cache_target_hits: ["F", "G"],
        created_at: ~N[2024-04-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["H", "I", "J", "K", "L"],
        local_cache_target_hits: ["H", "I", "J"],
        remote_cache_target_hits: ["K", "L"],
        created_at: ~N[2024-04-30 10:00:00]
      )

      # Previous period events
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["M", "N"],
        local_cache_target_hits: ["M"],
        remote_cache_target_hits: ["N"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 12
      assert_in_delta got.trend, 140.0, 0.1
      assert length(got.dates) == 30
      # Values at specific dates: April 1 = 3, April 15 = 4, April 30 = 5
      assert Enum.at(got.values, 0) == 3
      assert Enum.at(got.values, 14) == 4
      assert Enum.at(got.values, 29) == 5
      assert Enum.at(got.values, 1) == 0
      assert Enum.at(got.values, 13) == 0
    end

    test "returns zero when no hits exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no events created
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 0
      assert got.trend == 0.0
    end
  end

  describe "module_cache_misses_analytics/1" do
    test "returns module cache misses analytics with correct calculations" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # Current period: varying miss rates
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C", "D", "E"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["B"],
        created_at: ~N[2024-04-01 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["F", "G", "H", "I"],
        local_cache_target_hits: ["F"],
        remote_cache_target_hits: ["G"],
        created_at: ~N[2024-04-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["J", "K", "L", "M", "N", "O"],
        local_cache_target_hits: ["J", "K"],
        remote_cache_target_hits: ["L", "M"],
        created_at: ~N[2024-04-30 10:00:00]
      )

      # Previous period
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["P", "Q", "R"],
        local_cache_target_hits: ["P"],
        remote_cache_target_hits: ["Q"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 7
      assert_in_delta got.trend, 75.0, 0.1
      assert length(got.dates) == 30
      # Values at specific dates: April 1 = 3, April 15 = 2, April 30 = 2
      assert Enum.at(got.values, 0) == 3
      assert Enum.at(got.values, 14) == 2
      assert Enum.at(got.values, 29) == 2
      assert Enum.at(got.values, 1) == 0
      assert Enum.at(got.values, 13) == 0
    end

    test "returns zero when no misses exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # All targets have cache hits
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A", "B", "C"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-15 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 0
      assert length(got.values) == 30
      assert Enum.all?(got.values, &(&1 == 0))
    end
  end

  describe "module_cache_hit_rate_percentile/3" do
    test "returns module cache hit rate percentile analytics with descending order calculation" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # Current period: Create multiple events with varying hit rates for p99 calculation
      # Events on 2024-04-01
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["A1", "A2", "A3", "A4"],
        local_cache_target_hits: ["A1", "A2"],
        remote_cache_target_hits: ["A3"],
        created_at: ~N[2024-04-01 10:00:00]
      )

      # Events on 2024-04-15
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["B1", "B2", "B3", "B4"],
        local_cache_target_hits: ["B1", "B2", "B3"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-15 10:00:00]
      )

      # Events on 2024-04-30
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["C1", "C2", "C3", "C4"],
        local_cache_target_hits: ["C1", "C2", "C3"],
        remote_cache_target_hits: ["C4"],
        created_at: ~N[2024-04-30 10:00:00]
      )

      # Previous period
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["D1", "D2", "D3"],
        local_cache_target_hits: ["D1"],
        remote_cache_target_hits: ["D2"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.99,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert_in_delta got.avg_hit_rate, 75.0, 0.1
      assert_in_delta got.trend, 12.5, 0.1
      assert length(got.dates) == 30
      assert Enum.at(got.values, 0) != 0.0
      assert Enum.at(got.values, 14) != 0.0
      assert Enum.at(got.values, 29) != 0.0
      assert Enum.at(got.values, 1) == 0.0
    end

    test "returns zero percentile when no data exists" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no events created
      got =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.99,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "test_runs_metrics/1" do
    test "returns metrics and command event data for test runs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create test runs
      {:ok, test_run_one} =
        Tuist.Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      {:ok, test_run_two} =
        Tuist.Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "failure",
          scheme: "AnotherScheme",
          duration: 2000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          ran_at: ~N[2024-04-30 11:00:00.000000],
          test_modules: []
        })

      # Create test case runs for both test runs
      module_run_id_one = UUIDv7.generate()
      module_run_id_two = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_one.id,
          test_module_run_id: module_run_id_one,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          duration: 50,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testSuccess",
          status: 0,
          duration: 100,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testFailure",
          status: 1,
          duration: 200,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testAnother",
          status: 0,
          duration: 150,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        }
      ])

      # Create command events linked to test runs
      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_run_id: test_run_one.id,
          cacheable_targets: ["A", "B", "C"],
          local_cache_target_hits: ["A"],
          remote_cache_target_hits: ["B"],
          test_targets: ["TestA", "TestB"],
          local_test_target_hits: ["TestA"],
          remote_test_target_hits: [],
          duration: 5000,
          created_at: ~N[2024-04-30 10:00:00.000000]
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          subcommand: "test-without-building",
          test_run_id: test_run_two.id,
          cacheable_targets: ["D", "E", "F", "G"],
          local_cache_target_hits: [],
          remote_cache_target_hits: ["E", "F"],
          test_targets: ["TestC", "TestD", "TestE"],
          local_test_target_hits: ["TestC"],
          remote_test_target_hits: ["TestD"],
          duration: 3000,
          created_at: ~N[2024-04-30 11:00:00.000000]
        )

      # When
      got = Analytics.test_runs_metrics([test_run_one, test_run_two])

      # Then
      assert length(got) == 2

      # Find results for each test run
      result_one = Enum.find(got, &(&1.test_run_id == test_run_one.id))
      result_two = Enum.find(got, &(&1.test_run_id == test_run_two.id))

      # Verify test_run_one metrics (1 test case run)
      # Cache: 3 cacheable targets, 2 hits (A local, B remote) = 66%
      # Skipped: 1 local test target hit (TestA) = 1 skipped
      # Ran: 1 total - 1 skipped = 0 ran
      assert result_one.test_run_id == test_run_one.id
      assert result_one.total_tests == 1
      assert result_one.cache_hit_rate == "66 %"
      assert result_one.skipped_tests == 1
      assert result_one.ran_tests == 0

      # Verify test_run_two metrics (3 test case runs: 2 success, 1 failure)
      # Cache: 4 cacheable targets, 2 hits (E, F remote) = 50%
      # Skipped: 2 test target hits (TestC local, TestD remote) = 2 skipped
      # Ran: 3 total - 2 skipped = 1 ran
      assert result_two.test_run_id == test_run_two.id
      assert result_two.total_tests == 3
      assert result_two.cache_hit_rate == "50 %"
      assert result_two.skipped_tests == 2
      assert result_two.ran_tests == 1
    end

    test "handles test runs without command events" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tuist.Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      # Create test case runs but no command event
      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: UUIDv7.generate(),
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When
      got = Analytics.test_runs_metrics([test_run])

      # Then
      assert length(got) == 1
      result = List.first(got)

      # Without command event, no cache targets or test target hits
      # Cache: 0 cacheable targets = 0%
      # Skipped: 0 test target hits = 0 skipped
      # Ran: 1 total - 0 skipped = 1 ran
      assert result.test_run_id == test_run.id
      assert result.total_tests == 1
      assert result.cache_hit_rate == "0 %"
      assert result.skipped_tests == 0
      assert result.ran_tests == 1
    end
  end
end
