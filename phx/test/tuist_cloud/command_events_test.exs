defmodule TuistCloud.CommandEventsTest do
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts
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
    assert got == 1000.0
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

  test "returns duration analytics for the last thirty days" do
    # Given
    TuistCloud.Time
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
      created_at: ~N[2024-04-05 00:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 2000,
      created_at: ~N[2024-03-05 00:00:00]
    )

    # When
    got =
      CommandEvents.get_command_duration_analytics("generate",
        project_id: project.id,
        start_date: Date.add(Time.utc_now(), -30)
      )

    # Then
    assert got.average_durations[~D[2024-04-05]].value == 1500
    assert got.average_durations[~D[2024-04-30]].value == 1500
    assert got.average_durations[~D[2024-04-29]].value == 0
    assert got.trend == -25.0
    assert got.total_average_duration == 1500
  end

  test "returns runs analytics for the last 3 days" do
    # Given
    TuistCloud.Time
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
      created_at: ~N[2024-04-29 00:00:00]
    )

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 2000,
      created_at: ~N[2024-04-28 00:00:00]
    )

    # When
    got =
      CommandEvents.get_command_runs_analytics("generate",
        project_id: project.id,
        start_date: Date.add(Time.utc_now(), -2)
      )

    # Then
    assert got.values == [2, 1, 0]
    assert got.trend == 200
    assert got.runs_count == 3
  end

  test "returns cache hit rates for the last thirty days" do
    # Given
    TuistCloud.Time
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
      created_at: ~N[2024-04-30 03:00:00]
    )

    # When
    got =
      CommandEvents.get_cache_hit_rate_analytics(
        project_id: project.id,
        start_date: Date.add(Time.utc_now(), -30),
        end_date: DateTime.to_date(Time.utc_now())
      )

    # Then
    assert got.cache_hit_rates[~D[2024-04-30]].value == 0.5
    assert got.cache_hit_rate == 0.5
  end

  describe "update_cache_event_counts/0" do
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

  describe "get_cache_event/1" do
    test "returns cache download event" do
      # Given
      project = ProjectsFixtures.project_fixture()

      item = %{
        project_id: project.id,
        name: "a",
        event_type: :download,
        size: 1000
      }

      cache_event = CommandEvents.create_cache_event(item)

      # When
      got = CommandEvents.get_cache_event(%{name: "a"}, %{event_type: :download})

      # Then
      assert got == cache_event
    end
  end

  test "returns a trend when current_value is smaller" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 20.0, current_value: 10.0)

    # Then
    assert got == -50.0
  end

  test "returns a trend when current_value is bigger" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 10.0, current_value: 20.0)

    # Then
    assert got == 100.0
  end

  test "returns 0 for a trend if previous value is 0" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 0, current_value: 20.0)

    # Then
    assert got == 0
  end

  test "returns 0 for a trend if both values are 0" do
    # Given / When
    got = CommandEvents.get_trend(previous_value: 0.0, current_value: 0)

    # Then
    assert got == 0
  end

  test "updates cache event counts" do
    # Given
    Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    user_one = AccountsFixtures.user_fixture()
    account_one = Accounts.get_account_from_user(user_one)
    project_one = ProjectsFixtures.project_fixture(account_id: account_one.id)

    CommandEvents.create_cache_event(%{
      project_id: project_one.id,
      name: "a",
      event_type: :upload,
      size: 1000
    })

    CommandEvents.create_cache_event(%{
      project_id: project_one.id,
      name: "a",
      event_type: :download,
      size: 1000
    })

    CommandEvents.create_cache_event(%{
      project_id: project_one.id,
      name: "b",
      event_type: :download,
      size: 2000,
      created_at: ~N[2024-04-02 03:00:00]
    })

    project_two = ProjectsFixtures.project_fixture(account_id: account_one.id)

    CommandEvents.create_cache_event(%{
      project_id: project_two.id,
      name: "c",
      event_type: :upload,
      size: 3000,
      created_at: ~N[2024-04-01 03:00:00]
    })

    CommandEvents.create_cache_event(%{
      project_id: project_two.id,
      name: "c",
      event_type: :download,
      size: 3000,
      created_at: ~N[2024-04-01 03:00:00]
    })

    CommandEvents.create_cache_event(
      %{
        project_id: project_two.id,
        name: "c",
        event_type: :download,
        size: 10_000
      },
      created_at: ~N[2024-03-29 03:00:00]
    )

    user_two = AccountsFixtures.user_fixture()
    account_two = Accounts.get_account_from_user(user_two)
    project_three = ProjectsFixtures.project_fixture(account_id: account_two.id)

    CommandEvents.create_cache_event(%{
      project_id: project_three.id,
      name: "d",
      event_type: :download,
      size: 4000
    })

    Accounts.create_organization(%{name: "tuist-org"})

    # When
    CommandEvents.update_cache_event_counts()

    # Then
    assert Accounts.get_account_by_id(account_one.id).cache_download_event_count == 3
    assert Accounts.get_account_by_id(account_one.id).cache_upload_event_count == 2
    assert Accounts.get_account_by_id(account_two.id).cache_download_event_count == 1
    assert Accounts.get_account_by_id(account_two.id).cache_upload_event_count == 0
  end
end
