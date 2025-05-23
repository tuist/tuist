defmodule Tuist.Runs.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "builds_duration_analytics_grouped_by_category/3" do
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
        Analytics.builds_duration_analytics_grouped_by_category(
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
        Analytics.builds_duration_analytics_grouped_by_category(
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
        Analytics.builds_duration_analytics_grouped_by_category(
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

  describe "builds_percentile_durations/2" do
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
        Analytics.builds_percentile_durations(
          project.id,
          0.5,
          start_date: ~D[2024-04-28]
        )

      # Then
      assert got.values == [0, 1500.0, 3000.0]
    end
  end

  describe "builds_analytics/2" do
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
        Analytics.builds_analytics(
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
    test "returns cache hit rates for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
