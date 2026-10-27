defmodule Tuist.CommandEvents.CommandArgumentsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @computed_fields ~w(cacheable_targets_count local_cache_hits_count remote_cache_hits_count test_targets_count local_test_hits_count remote_test_hits_count hit_rate)a

  test "buffered arguments survive canonical reads and every optimized list" do
    project = ProjectsFixtures.project_fixture()
    arguments = ["generate", "--configuration", "Debug Scheme", "FocusedTargetName", "", "a\"b", "🎯"]
    event = CommandEventsFixtures.command_event_fixture(project_id: project.id, command_arguments: arguments)

    assert {:ok, reloaded} = CommandEvents.get_command_event_by_id(event.id)
    assert reloaded.command_arguments == Enum.join(arguments, " ")
    assert Event.recorded_command_arguments(reloaded) == arguments

    for order_by <- [:ran_at, :duration, :hit_rate], name_filter? <- [false, true] do
      filters = [%{field: :project_id, op: :==, value: project.id}]
      filters = if name_filter?, do: filters ++ [%{field: :name, op: :==, value: "generate"}], else: filters

      assert {[listed], _meta} =
               CommandEvents.list_command_events(%{
                 first: 10,
                 filters: filters,
                 order_by: [order_by],
                 order_directions: [:desc]
               })

      assert listed.id == event.id
      assert listed.command_arguments == Enum.join(arguments, " ")
      assert Event.recorded_command_arguments(listed) == arguments
    end
  end

  test "an old writer omitting both columns remains unknown" do
    event = CommandEventsFixtures.command_event_fixture(command_arguments: ["generate"])
    legacy_id = UUIDv7.generate()

    legacy_attrs =
      event
      |> insertable_attrs()
      |> Map.drop(@computed_fields ++ [:command_arguments_array, :command_arguments_recorded])
      |> Map.put(:id, legacy_id)
      |> Map.put(:command_arguments, "generate --configuration Debug Scheme")

    IngestRepo.insert_all(Event, [legacy_attrs])

    assert {:ok, legacy} = CommandEvents.get_command_event_by_id(legacy_id)
    refute legacy.command_arguments_recorded
    assert legacy.command_arguments_array == []
    assert Event.recorded_command_arguments(legacy) == nil
  end

  test "a newer legacy copy does not borrow arguments from an older recorded copy" do
    project = ProjectsFixtures.project_fixture()
    id = UUIDv7.generate()

    CommandEventsFixtures.command_event_fixture(
      id: id,
      project_id: project.id,
      command_arguments: ["generate", "FocusedTarget"],
      created_at: ~U[2026-10-01 12:00:00.000000Z]
    )

    CommandEventsFixtures.command_event_fixture(
      id: id,
      project_id: project.id,
      command_arguments: "generate --configuration Debug Scheme",
      created_at: ~U[2026-10-01 12:00:01.000000Z]
    )

    {events, _meta} =
      CommandEvents.list_command_events(%{
        first: 10,
        filters: [%{field: :project_id, op: :==, value: project.id}],
        order_by: [:ran_at],
        order_directions: [:desc]
      })

    assert events != []

    for event <- events do
      assert event.command_arguments == "generate --configuration Debug Scheme"
      assert Event.recorded_command_arguments(event) == nil
    end
  end
end
