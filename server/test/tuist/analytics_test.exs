defmodule Tuist.AnalyticsTest do
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
        duration: 3000,
        xcode_version: "15.0",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      # When
      got = Analytics.builds_duration_analytics_grouped_by_category(project.id, :xcode_version)

      # Then
      assert length(got) == 2

      category_14_3_1 = Enum.find(got, fn analytics -> analytics.category == "14.3.1" end)
      assert category_14_3_1.category == "14.3.1"
      assert category_14_3_1.value == 1500.0

      category_15_0 = Enum.find(got, fn analytics -> analytics.category == "15.0" end)
      assert category_15_0.category == "15.0"
      assert category_15_0.value == 3000.0
    end

    test "returns duration analytics grouped by model_identifier" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        model_identifier: "MacBookPro18,1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        model_identifier: "MacBookPro18,1",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 3000,
        model_identifier: "MacStudio1,2",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      # When
      got = Analytics.builds_duration_analytics_grouped_by_category(project.id, :model_identifier)

      # Then
      assert length(got) == 2

      macbook_category = Enum.find(got, fn analytics -> analytics.category == "MacBookPro18,1" end)
      assert macbook_category.category == "MacBookPro18,1"
      assert macbook_category.value == 1500.0

      mac_studio_category = Enum.find(got, fn analytics -> analytics.category == "MacStudio1,2" end)
      assert mac_studio_category.category == "MacStudio1,2"
      assert mac_studio_category.value == 3000.0
    end

    test "returns duration analytics grouped by macos_version" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 2000,
        macos_version: "13.0",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 1000,
        macos_version: "13.0",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        id: UUIDv7.generate(),
        project_id: project.id,
        duration: 3000,
        macos_version: "14.0",
        inserted_at: ~U[2024-04-30 03:00:00Z]
      )

      # When
      got = Analytics.builds_duration_analytics_grouped_by_category(project.id, :macos_version)

      # Then
      assert length(got) == 2

      category_13_0 = Enum.find(got, fn analytics -> analytics.category == "13.0" end)
      assert category_13_0.category == "13.0"
      assert category_13_0.value == 1500.0

      category_14_0 = Enum.find(got, fn analytics -> analytics.category == "14.0" end)
      assert category_14_0.category == "14.0"
      assert category_14_0.value == 3000.0
    end
  end

  describe "build_time_analytics/1 with PostgreSQL" do
    test "returns zeros when ClickHouse is not configured" do
      # Given
      stub(Tuist.Environment, :clickhouse_configured?, fn -> false end)
      project = ProjectsFixtures.project_fixture()

      # When
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      # Should return zeros when ClickHouse is not configured
      assert got.total_time_saved == 0
      assert got.total_build_time == 0
      assert got.actual_build_time == 0
    end
  end

  describe "build_time_analytics/1 with ClickHouse" do
    test "returns build time analytics for the last 30 days by default" do
      # Given
      copy(Tuist.ClickHouseRepo)
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      stub(Tuist.Environment, :clickhouse_configured?, fn -> true end)
      project = ProjectsFixtures.project_fixture()

      # Create command events
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

      command_event_3 =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          created_at: ~N[2024-04-15 10:00:00],
          duration: 1000
        )

      # Mock ClickHouse repository calls
      stub(Tuist.ClickHouseRepo, :all, fn _query ->
        [command_event_1.id, command_event_2.id, command_event_3.id]
      end)

      stub(Tuist.ClickHouseRepo, :one, fn _query ->
        10_000  # Total binary_build_duration: 5000 + 3000 + 2000
      end)

      # When
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      # Total time saved: 10000ms (from mocked ClickHouse)
      assert got.total_time_saved == 10_000

      # Total build time = time_saved + command_events_duration = 10000 + (1500 + 2000 + 1000) = 14500ms
      assert got.total_build_time == 14_500
    end

    test "handles ClickHouse path when no command events found" do
      # Given
      copy(Tuist.ClickHouseRepo)
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      stub(Tuist.Environment, :clickhouse_configured?, fn -> true end)
      project = ProjectsFixtures.project_fixture()

      # Mock ClickHouse repository calls to return empty results
      stub(Tuist.ClickHouseRepo, :all, fn _query -> [] end)

      # When
      got = Analytics.build_time_analytics(project_id: project.id)

      # Then
      # Should return 0 values when no events are found
      assert got.total_time_saved == 0
      assert got.total_build_time == 0
    end
  end
end