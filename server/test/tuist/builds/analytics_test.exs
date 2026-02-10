defmodule Tuist.Builds.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Builds.Analytics
  alias Tuist.IngestRepo
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
          start_datetime: DateTime.add(DateTime.utc_now(), -30, :day)
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
          start_datetime: DateTime.add(DateTime.utc_now(), -30, :day)
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
          start_datetime: DateTime.add(DateTime.utc_now(), -30, :day)
        )

      # Then
      assert Enum.sort_by(got, & &1.category) == [
               %{value: 1500.0, category: "13.5.1"},
               %{value: 1500.0, category: "14.0.0"}
             ]
    end
  end

  describe "build_duration_analytics/2" do
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          configuration: "Debug"
        )

      # Then
      assert got.values == [0, 0, 2000.0]
      assert got.total_average_duration == 2000
    end

    test "returns hourly duration analytics for a single day range" do
      # Given - stub DateTime.utc_now to a known time
      # Hourly range generates hours from start of day up to utc_now
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 11:00:00Z] end)
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
        inserted_at: ~U[2024-04-30 08:00:00Z]
      )

      # When
      got =
        Analytics.build_duration_analytics(
          project.id,
          start_datetime: ~U[2024-04-30 00:00:00Z],
          end_datetime: ~U[2024-04-30 11:00:00Z]
        )

      # Then - shows hours from 00:00 to 11:00, which is 12 hours
      assert length(got.dates) == 12
      assert length(got.values) == 12
      # Hourly ranges return DateTime structs
      assert ~U[2024-04-30 03:00:00Z] in got.dates
      assert ~U[2024-04-30 08:00:00Z] in got.dates

      # Verify the actual values match the dates
      # At 03:00, there are 2 builds with duration 2000 and 1000, so average is 1500
      hour_03_index = Enum.find_index(got.dates, &(&1 == ~U[2024-04-30 03:00:00Z]))
      assert Enum.at(got.values, hour_03_index) == 1500.0

      # At 08:00, there's 1 build with duration 1500
      hour_08_index = Enum.find_index(got.dates, &(&1 == ~U[2024-04-30 08:00:00Z]))
      assert Enum.at(got.values, hour_08_index) == 1500.0

      # Other hours should have 0 values
      assert Enum.count(got.values, &(&1 == 0)) == 10
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
          start_datetime: ~U[2024-04-28 00:00:00Z]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then
      # days_delta = 3, so previous period is April 25-28
      # Previous p50([500, 1000, 1500]) = 1000, Current p50([1000, 2000, 3000]) = 2000
      # Trend from 1000 to 2000 = +100%
      assert got.trend == 100.0
      assert got.values == [1000.0, 2000.0, 3000.0, 0]
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      assert got.values == [0, 1, 2]
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.trend == 200
      assert got.count == 3
    end

    test "returns hourly build counts for a single day range" do
      # Given - stub DateTime.utc_now to a known time
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 11:00:00Z] end)
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
        inserted_at: ~U[2024-04-30 08:00:00Z]
      )

      # When
      got =
        Analytics.build_analytics(
          project.id,
          start_datetime: ~U[2024-04-30 00:00:00Z],
          end_datetime: ~U[2024-04-30 11:00:00Z]
        )

      # Then - 12 hours from 00:00 to 11:00
      assert length(got.dates) == 12
      assert length(got.values) == 12

      # At 03:00, there are 2 builds
      hour_03_index = Enum.find_index(got.dates, &(&1 == ~U[2024-04-30 03:00:00Z]))
      assert Enum.at(got.values, hour_03_index) == 2

      # At 08:00, there is 1 build
      hour_08_index = Enum.find_index(got.dates, &(&1 == ~U[2024-04-30 08:00:00Z]))
      assert Enum.at(got.values, hour_08_index) == 1

      # Other hours should have 0 builds
      assert Enum.count(got.values, &(&1 == 0)) == 10

      # Total count
      assert got.count == 3
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now(),
          is_ci: true
        )

      # Then
      assert got.values == [0, 0.5, 0.5]
      assert got.hit_rate == 0.5
    end
  end

  describe "selective_testing_analytics_with_percentiles/1" do
    test "returns selective testing analytics with percentile values" do
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
        Analytics.selective_testing_analytics_with_percentiles(
          project_id: project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
        )

      # Then
      assert got.values == [0, 0, 0.5]
      assert got.hit_rate == 0.5
      assert Map.has_key?(got, :p50)
      assert Map.has_key?(got, :p90)
      assert Map.has_key?(got, :p99)
      assert Map.has_key?(got, :p50_values)
      assert Map.has_key?(got, :p90_values)
      assert Map.has_key?(got, :p99_values)
      assert is_float(got.p50)
      assert is_float(got.p90)
      assert is_float(got.p99)
      assert is_list(got.p50_values)
      assert is_list(got.p90_values)
      assert is_list(got.p99_values)
      assert length(got.p50_values) == length(got.dates)
      assert length(got.p90_values) == length(got.dates)
      assert length(got.p99_values) == length(got.dates)
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
        status: "success",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # Create failed build
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-04-29 01:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
        status: "failure",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
        status: "success",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
      # Note: builds must be after 10:20:30 to be in the previous period window
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-26 12:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-04-26 11:00:00Z]
      )

      # Current period (last 2 days): 3 success out of 4 builds = 75%
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-04-29 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-04-29 01:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          end_datetime: DateTime.utc_now()
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
        status: "success",
        scheme: "AppOne",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        scheme: "AppOne",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        scheme: "AppOne",
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        scheme: "AppOne",
        inserted_at: ~U[2024-04-28 02:00:00Z]
      )

      # AppTwo builds: all failures
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        scheme: "AppTwo",
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -3, :day),
          end_datetime: DateTime.utc_now(),
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
        status: "success",
        configuration: "Debug",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        configuration: "Debug",
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        configuration: "Debug",
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        configuration: "Release",
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        configuration: "Release",
        inserted_at: ~U[2024-04-29 02:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -3, :day),
          end_datetime: DateTime.utc_now(),
          configuration: "Debug"
        )

      # Then
      assert_in_delta got.success_rate, 0.6667, 0.0001
    end

    test "respects build tag filter" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Builds with "nightly" tag: 2 success, 1 failure = 66.7%
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        custom_tags: ["nightly", "ci"],
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "success",
        custom_tags: ["nightly"],
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        custom_tags: ["nightly", "release"],
        inserted_at: ~U[2024-04-28 03:00:00Z]
      )

      # Builds without "nightly" tag: all failures
      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        custom_tags: ["ci"],
        inserted_at: ~U[2024-04-30 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        status: "failure",
        custom_tags: [],
        inserted_at: ~U[2024-04-29 02:00:00Z]
      )

      # When
      got =
        Analytics.build_success_rate_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -3, :day),
          end_datetime: DateTime.utc_now(),
          tag: "nightly"
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
          start_datetime: ~U[2024-04-15 00:00:00Z],
          end_datetime: ~U[2024-04-29 23:59:59Z]
        )

      # Then - only the first event should be included
      assert got.actual_build_time == 1000
      assert got.total_time_saved == 2000
      assert got.total_build_time == 3000
    end

    test "handles nil duration events correctly" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          ~U[2024-04-29 00:00:00Z],
          ~U[2024-04-30 23:59:59Z],
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
          ~U[2024-04-29 00:00:00Z],
          ~U[2024-04-30 23:59:59Z],
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
          ~U[2024-03-01 00:00:00Z],
          ~U[2024-04-30 23:59:59Z],
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
          ~U[2024-04-29 00:00:00Z],
          ~U[2024-04-30 23:59:59Z],
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["AA", "BB", "CC", "DD", "EE"],
        local_cache_target_hits: ["AA"],
        remote_cache_target_hits: ["BB"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["ZZ"],
        local_cache_target_hits: [],
        remote_cache_target_hits: [],
        created_at: ~N[2024-03-10 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no command events created
      got =
        Analytics.module_cache_hit_rate_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "module_cache_hits_analytics/1" do
    test "returns module cache hits analytics with correct totals" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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

      # Previous period events (need 5 total hits for 140% trend: (12-5)/5*100 = 140%)
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["M", "N"],
        local_cache_target_hits: ["M"],
        remote_cache_target_hits: ["N"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["O", "P", "Q"],
        local_cache_target_hits: ["O", "P"],
        remote_cache_target_hits: ["Q"],
        created_at: ~N[2024-03-10 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no events created
      got =
        Analytics.module_cache_hits_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.total_count == 0
      assert got.trend == 0.0
    end
  end

  describe "module_cache_misses_analytics/1" do
    test "returns module cache misses analytics with correct calculations" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["P", "Q", "R"],
        local_cache_target_hits: ["P"],
        remote_cache_target_hits: ["Q"],
        created_at: ~N[2024-03-15 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        cacheable_targets: ["S", "T", "U"],
        local_cache_target_hits: [],
        remote_cache_target_hits: [],
        created_at: ~N[2024-03-10 10:00:00]
      )

      # When
      got =
        Analytics.module_cache_misses_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
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
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
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
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      stub(Date, :utc_today, fn -> ~D[2024-04-30] end)
      project = ProjectsFixtures.project_fixture()

      # When - no events created
      got =
        Analytics.module_cache_hit_rate_percentile(
          project.id,
          0.99,
          project_id: project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "build_duration_metric_by_count/3" do
    test "returns average duration for last N builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create builds with different durations (newest first)
      for {duration, i} <- [{1200, 1}, {1000, 2}, {800, 3}, {600, 4}, {400, 5}] do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: duration,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # When - get average of last 3 builds (1200, 1000, 800)
      result = Analytics.build_duration_metric_by_count(project.id, :average, limit: 3)

      # Then
      assert result == 1000.0
    end

    test "returns p90 duration for last N builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create 10 builds with durations 100, 200, ..., 1000
      for i <- 1..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: (11 - i) * 100,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # When - get p90 of all 10 builds
      result = Analytics.build_duration_metric_by_count(project.id, :p90, limit: 10)

      # Then - p90 of sorted [100, 200, ..., 1000] at index trunc(10*0.9)=9 is 1000
      assert result == 1000
    end

    test "returns nil when no builds exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Analytics.build_duration_metric_by_count(project.id, :average, limit: 5)

      # Then
      assert result == nil
    end

    test "respects offset parameter" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create 6 builds: current (1200, 1200, 1200) and previous (1000, 1000, 1000)
      for {duration, i} <- [{1200, 1}, {1200, 2}, {1200, 3}, {1000, 4}, {1000, 5}, {1000, 6}] do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: duration,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # When - get average of builds 4-6 (offset: 3)
      result = Analytics.build_duration_metric_by_count(project.id, :average, limit: 3, offset: 3)

      # Then - average of [1000, 1000, 1000]
      assert result == 1000.0
    end
  end

  describe "build_cache_hit_rate_metric_by_count/3" do
    test "returns average cache hit rate for last N builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create builds with different cache hit rates
      # Build 1: 80% hit rate (80/100)
      {:ok, _} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          cacheable_tasks_count: 100,
          cacheable_task_local_hits_count: 50,
          cacheable_task_remote_hits_count: 30,
          inserted_at: DateTime.add(DateTime.utc_now(), -1, :minute)
        )

      # Build 2: 60% hit rate (60/100)
      {:ok, _} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          cacheable_tasks_count: 100,
          cacheable_task_local_hits_count: 40,
          cacheable_task_remote_hits_count: 20,
          inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)
        )

      # When - get average of both builds
      result = Analytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 2)

      # Then - average of [0.8, 0.6] = 0.7
      assert result == 0.7
    end

    test "excludes builds without cacheable tasks" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Build with cache data
      {:ok, _} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          cacheable_tasks_count: 100,
          cacheable_task_local_hits_count: 70,
          cacheable_task_remote_hits_count: 0,
          inserted_at: DateTime.add(DateTime.utc_now(), -1, :minute)
        )

      # Build without cache data (cacheable_tasks_count = 0)
      {:ok, _} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          cacheable_tasks_count: 0,
          inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)
        )

      # When - get average (should only include build with cache data)
      result = Analytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 10)

      # Then - only the 70% hit rate build is included
      assert result == 0.7
    end

    test "returns nil when no builds with cache data exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Build without cache data
      {:ok, _} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          cacheable_tasks_count: 0
        )

      # When
      result = Analytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 5)

      # Then
      assert result == nil
    end

    test "returns p90 cache hit rate" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create 10 builds with hit rates: 10%, 20%, ..., 100%
      for i <- 1..10 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: (11 - i) * 10,
            cacheable_task_remote_hits_count: 0,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # When - get p90 of all 10 builds
      result = Analytics.build_cache_hit_rate_metric_by_count(project.id, :p90, limit: 10)

      # Then - p90 of sorted [0.1, 0.2, ..., 1.0] at index trunc(10*0.1)=1 is 0.2
      # (for cache hit rate, higher is better, so p90 gives the lower 10th percentile)
      assert result == 0.2
    end

    test "respects offset parameter for comparing current vs previous" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Current builds: 90% hit rate
      for i <- 1..3 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 90,
            cacheable_task_remote_hits_count: 0,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # Previous builds: 70% hit rate
      for i <- 4..6 do
        {:ok, _} =
          RunsFixtures.build_fixture(
            project_id: project.id,
            duration: 1000,
            cacheable_tasks_count: 100,
            cacheable_task_local_hits_count: 70,
            cacheable_task_remote_hits_count: 0,
            inserted_at: DateTime.add(DateTime.utc_now(), -i, :minute)
          )
      end

      # When - get current (offset: 0) and previous (offset: 3)
      current = Analytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 3, offset: 0)
      previous = Analytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 3, offset: 3)

      # Then (use assert_in_delta for floating point comparison)
      assert_in_delta current, 0.9, 0.001
      assert_in_delta previous, 0.7, 0.001
    end
  end
end
