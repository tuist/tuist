defmodule Tuist.Runs.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Runs.Analytics
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

      # Current period (2024-04-28 to 2024-04-30): builds with p50 of 2000
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

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, start_date, end_date, _opts ->
        case {start_date, end_date} do
          {~D[2024-04-01], ~D[2024-04-30]} ->
            %{
              cacheable_targets_count: 100,
              local_cache_hits_count: 40,
              remote_cache_hits_count: 20
            }

          {~D[2024-03-03], ~D[2024-04-01]} ->
            %{
              cacheable_targets_count: 80,
              local_cache_hits_count: 20,
              remote_cache_hits_count: 20
            }
        end
      end)

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        [
          %{date: "2024-04-01", cacheable_targets: 30, local_cache_target_hits: 10, remote_cache_target_hits: 5},
          %{date: "2024-04-15", cacheable_targets: 35, local_cache_target_hits: 15, remote_cache_target_hits: 8},
          %{date: "2024-04-30", cacheable_targets: 35, local_cache_target_hits: 15, remote_cache_target_hits: 7}
        ]
      end)

      # When
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.avg_hit_rate == 60.0
      assert got.trend == 20.0
      assert length(got.dates) == 3
      assert got.dates == ["2024-04-01", "2024-04-15", "2024-04-30"]
      assert got.values == [50.0, 65.7, 62.9]
    end

    test "returns zero hit rate when no cacheable targets exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, _start_date, _end_date, _opts ->
        %{
          cacheable_targets_count: 0,
          local_cache_hits_count: 0,
          remote_cache_hits_count: 0
        }
      end)

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        []
      end)

      # When
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

    test "handles nil values correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, _start_date, _end_date, _opts ->
        %{
          cacheable_targets_count: nil,
          local_cache_hits_count: nil,
          remote_cache_hits_count: nil
        }
      end)

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        []
      end)

      # When
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

    test "calculates trend correctly when improving" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate, fn _project_id, start_date, end_date, _opts ->
        case {start_date, end_date} do
          {~D[2024-04-01], ~D[2024-04-30]} ->
            %{cacheable_targets_count: 100, local_cache_hits_count: 50, remote_cache_hits_count: 30}

          {~D[2024-03-03], ~D[2024-04-01]} ->
            %{cacheable_targets_count: 100, local_cache_hits_count: 30, remote_cache_hits_count: 10}
        end
      end)

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        []
      end)

      # When
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.avg_hit_rate == 80.0
      assert got.trend == 100.0
    end
  end

  describe "module_cache_hits_analytics/1" do
    test "returns module cache hits analytics with correct totals" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id, start_date, _end_date, _date_period, _time_bucket, _opts ->
        case start_date do
          ~D[2024-04-01] ->
            [
              %{date: "2024-04-01", local_cache_target_hits: 10, remote_cache_target_hits: 5},
              %{date: "2024-04-15", local_cache_target_hits: 15, remote_cache_target_hits: 8},
              %{date: "2024-04-30", local_cache_target_hits: 20, remote_cache_target_hits: 12}
            ]

          ~D[2024-03-03] ->
            [
              %{date: "2024-03-03", local_cache_target_hits: 8, remote_cache_target_hits: 4},
              %{date: "2024-03-15", local_cache_target_hits: 10, remote_cache_target_hits: 6}
            ]
        end
      end)

      # When
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 70
      assert got.trend == 150.0
      assert length(got.dates) == 3
      assert got.values == [15, 23, 32]
    end

    test "returns zero when no hits exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        []
      end)

      # When
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

    test "handles nil hit counts correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        [
          %{date: "2024-04-01", local_cache_target_hits: nil, remote_cache_target_hits: 5},
          %{date: "2024-04-15", local_cache_target_hits: 10, remote_cache_target_hits: nil}
        ]
      end)

      # When
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 15
      assert got.values == [5, 10]
    end
  end

  describe "module_cache_misses_analytics/1" do
    test "returns module cache misses analytics with correct calculations" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id, start_date, _end_date, _date_period, _time_bucket, _opts ->
        case start_date do
          ~D[2024-04-01] ->
            [
              %{date: "2024-04-01", cacheable_targets: 30, local_cache_target_hits: 10, remote_cache_target_hits: 5},
              %{date: "2024-04-15", cacheable_targets: 40, local_cache_target_hits: 15, remote_cache_target_hits: 10},
              %{date: "2024-04-30", cacheable_targets: 50, local_cache_target_hits: 20, remote_cache_target_hits: 15}
            ]

          ~D[2024-03-03] ->
            [
              %{date: "2024-03-03", cacheable_targets: 25, local_cache_target_hits: 8, remote_cache_target_hits: 7},
              %{date: "2024-03-15", cacheable_targets: 30, local_cache_target_hits: 10, remote_cache_target_hits: 8}
            ]
        end
      end)

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 45
      assert_in_delta got.trend, 104.5, 0.1
      assert length(got.dates) == 3
      assert got.values == [15, 15, 15]
    end

    test "returns zero when no misses exist" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        [
          %{date: "2024-04-01", cacheable_targets: 10, local_cache_target_hits: 5, remote_cache_target_hits: 5}
        ]
      end)

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 0
      assert got.values == [0]
    end

    test "handles nil values correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        [
          %{date: "2024-04-01", cacheable_targets: 30, local_cache_target_hits: nil, remote_cache_target_hits: 10},
          %{date: "2024-04-15", cacheable_targets: 40, local_cache_target_hits: 15, remote_cache_target_hits: nil}
        ]
      end)

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.total_count == 45
      assert got.values == [20, 25]
    end

    test "never returns negative misses" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rates, fn _project_id,
                                                     _start_date,
                                                     _end_date,
                                                     _date_period,
                                                     _time_bucket,
                                                     _opts ->
        [
          %{date: "2024-04-01", cacheable_targets: 10, local_cache_target_hits: 8, remote_cache_target_hits: 5}
        ]
      end)

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.values == [0]
    end
  end

  describe "module_cache_hit_rate_percentile/3" do
    test "returns module cache hit rate percentile analytics with descending order calculation" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate_period_percentile, fn _project_id,
                                                                       start_date,
                                                                       _end_date,
                                                                       _percentile,
                                                                       _opts ->
        case start_date do
          ~D[2024-04-01] -> 75.5
          ~D[2024-03-03] -> 60.0
        end
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate_percentiles, fn _project_id,
                                                                 _start_date,
                                                                 _end_date,
                                                                 _date_period,
                                                                 _time_bucket,
                                                                 _percentile,
                                                                 _opts ->
        [
          %{date: "2024-04-01", percentile_hit_rate: 70.5},
          %{date: "2024-04-15", percentile_hit_rate: 75.8},
          %{date: "2024-04-30", percentile_hit_rate: 80.2}
        ]
      end)

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
      assert got.avg_hit_rate == 75.5
      assert_in_delta got.trend, 25.8, 0.1
      assert length(got.dates) == 3
      assert got.values == [70.5, 75.8, 80.2]
    end

    test "returns zero percentile when no data exists" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate_period_percentile, fn _project_id,
                                                                       _start_date,
                                                                       _end_date,
                                                                       _percentile,
                                                                       _opts ->
        nil
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate_percentiles, fn _project_id,
                                                                 _start_date,
                                                                 _end_date,
                                                                 _date_period,
                                                                 _time_bucket,
                                                                 _percentile,
                                                                 _opts ->
        []
      end)

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
      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
    end

    test "handles nil percentile_hit_rate values correctly" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate_period_percentile, fn _project_id,
                                                                       _start_date,
                                                                       _end_date,
                                                                       _percentile,
                                                                       _opts ->
        50.0
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate_percentiles, fn _project_id,
                                                                 _start_date,
                                                                 _end_date,
                                                                 _date_period,
                                                                 _time_bucket,
                                                                 _percentile,
                                                                 _opts ->
        [
          %{date: "2024-04-01", percentile_hit_rate: nil},
          %{date: "2024-04-15", percentile_hit_rate: 45.0}
        ]
      end)

      # When
      got =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.9,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got.values == [0.0, 45.0]
    end

    test "correctly calculates different percentiles" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate_period_percentile, fn _project_id,
                                                                       _start_date,
                                                                       _end_date,
                                                                       percentile,
                                                                       _opts ->
        case percentile do
          0.99 -> 95.0
          0.9 -> 85.0
          0.5 -> 60.0
        end
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate_percentiles, fn _project_id,
                                                                 _start_date,
                                                                 _end_date,
                                                                 _date_period,
                                                                 _time_bucket,
                                                                 _percentile,
                                                                 _opts ->
        []
      end)

      # When p99
      got_p99 =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.99,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # When p90
      got_p90 =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.9,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # When p50
      got_p50 =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.5,
          project_id: project.id,
          start_date: ~D[2024-04-01],
          end_date: ~D[2024-04-30]
        )

      # Then
      assert got_p99.avg_hit_rate == 95.0
      assert got_p90.avg_hit_rate == 85.0
      assert got_p50.avg_hit_rate == 60.0
    end

    test "rounds percentile values to one decimal place" do
      # Given
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      stub(Tuist.CommandEvents, :cache_hit_rate_period_percentile, fn _project_id,
                                                                       _start_date,
                                                                       _end_date,
                                                                       _percentile,
                                                                       _opts ->
        75.567890
      end)

      stub(Tuist.CommandEvents, :cache_hit_rate_percentiles, fn _project_id,
                                                                 _start_date,
                                                                 _end_date,
                                                                 _date_period,
                                                                 _time_bucket,
                                                                 _percentile,
                                                                 _opts ->
        [
          %{date: "2024-04-01", percentile_hit_rate: 70.123456}
        ]
      end)

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
      assert got.avg_hit_rate == 75.6
      assert got.values == [70.1]
    end
  end
end
