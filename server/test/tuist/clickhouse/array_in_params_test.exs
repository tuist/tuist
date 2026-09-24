defmodule Tuist.ClickHouse.ArrayInParamsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Builds.Build
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "filters by more integers than ClickHouse accepts as separate HTTP fields" do
    # Given
    project = ProjectsFixtures.project_fixture()
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
    project_ids = Enum.to_list(-2_000..-1//1) ++ [project.id]

    # When
    ids = ClickHouseRepo.all(from(e in Event, where: e.project_id in ^project_ids, select: e.id))

    # Then
    assert ids == [event.id]
  end

  test "excludes more UUIDs than ClickHouse accepts as separate HTTP fields" do
    # Given
    project = ProjectsFixtures.project_fixture()
    excluded = CommandEventsFixtures.command_event_fixture(project_id: project.id)
    kept = CommandEventsFixtures.command_event_fixture(project_id: project.id)
    excluded_ids = [excluded.id | Enum.map(1..1_500, fn _ -> UUIDv7.generate() end)]

    # When
    ids =
      ClickHouseRepo.all(from(e in Event, where: e.project_id == ^project.id and e.id not in ^excluded_ids, select: e.id))

    # Then
    assert ids == [kept.id]
  end

  test "filters inside a subquery" do
    # Given
    project = ProjectsFixtures.project_fixture()
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id)
    project_ids = Enum.to_list(-2_000..-1//1) ++ [project.id]
    matching = from(e in Event, where: e.project_id in ^project_ids, select: %{id: e.id})

    # When
    ids = ClickHouseRepo.all(from(m in subquery(matching), select: m.id))

    # Then
    assert ids == [event.id]
  end

  test "preloads an association of more parents than ClickHouse accepts as separate HTTP fields" do
    # Given
    {:ok, build} =
      RunsFixtures.build_fixture(
        machine_metrics: [
          %{
            timestamp: 1_700_000_000.0,
            cpu_usage_percent: 45.5,
            memory_used_bytes: 8_000_000_000,
            memory_total_bytes: 16_000_000_000,
            network_bytes_in: 1_000_000,
            network_bytes_out: 500_000,
            disk_bytes_read: 2_000_000,
            disk_bytes_written: 1_500_000
          }
        ]
      )

    builds = [build | Enum.map(1..1_500, fn _ -> %Build{id: UUIDv7.generate()} end)]

    # When
    [preloaded | others] = ClickHouseRepo.preload(builds, :machine_metrics)

    # Then
    assert [%{cpu_usage_percent: 45.5}] = preloaded.machine_metrics
    assert Enum.all?(others, &(&1.machine_metrics == []))
  end

  test "leaves an empty list matching nothing" do
    # Given
    project = ProjectsFixtures.project_fixture()
    CommandEventsFixtures.command_event_fixture(project_id: project.id)

    # When
    ids = ClickHouseRepo.all(from(e in Event, where: e.project_id in ^[], select: e.id))

    # Then
    assert ids == []
  end
end
