defmodule TuistCloud.CommandEventsTest do
  alias TuistCloud.CommandEvents
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Time
  use TuistCloud.DataCase
  use Mimic

  test "returns command average duration" do
    # Given
    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    project = ProjectsFixtures.project_fixture()

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1500,
      created_at: ~N[2024-03-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 500,
      created_at: ~N[2024-03-05 00:00:00]
    )

    # When
    got =
      CommandEvents.get_total_command_period_average_duration(
        "generate",
        project.id,
        start_date: Date.add(Time.utc_now(), -60),
        end_date: Date.add(Time.utc_now(), -30)
      )

    # Then
    assert got == 1.0
  end

  test "returns average duration for the last thirty days" do
    # Given
    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    project = ProjectsFixtures.project_fixture()

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 20,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 10,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "fetch",
      duration: 10,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 5,
      created_at: ~N[2024-04-05 00:00:00]
    )

    # When
    got = CommandEvents.get_command_average("generate", project.id)

    # Then
    assert got[~D[2024-04-05]].value == 5
    assert got[~D[2024-04-30]].value == 15
    assert got[~D[2024-04-29]].value == 0
  end

  test "returns cache hit rates for the last thirty days" do
    # Given
    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    project = ProjectsFixtures.project_fixture()

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "A",
      remote_cache_target_hits: "C",
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: "A;B;C;D",
      local_cache_target_hits: "E;F",
      remote_cache_target_hits: "",
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      cacheable_targets: "A;B",
      local_cache_target_hits: "",
      remote_cache_target_hits: "B",
      created_at: ~N[2024-04-30 03:00:00]
    )

    # When
    got = CommandEvents.get_cache_hit_rates(project.id)
    got_cache_hit_rate = CommandEvents.get_cache_hit_rate(project.id)

    # Then
    assert got[~D[2024-04-30]].value == 0.5
    assert got_cache_hit_rate == 0.5
  end

  test "returns average duration for the last year" do
    # Given
    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    project = ProjectsFixtures.project_fixture()

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 20,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 10,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "fetch",
      duration: 10,
      created_at: ~N[2024-04-30 03:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 5,
      created_at: ~N[2024-03-05 00:00:00]
    )

    # When
    got =
      CommandEvents.get_command_average("generate", project.id,
        start_date: Date.add(Time.utc_now(), -365)
      )

    # Then
    assert got[~D[2024-03-05]].value == 5
    assert got[~D[2024-04-30]].value == 15
    assert got[~D[2024-01-29]].value == 0
  end
end
