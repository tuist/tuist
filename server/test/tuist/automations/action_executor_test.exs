defmodule Tuist.Automations.ActionExecutorTest do
  # Integration test: drives ActionExecutor through the real
  # Tests.update_test_case down to ClickHouse so the merged-attrs path
  # (the fix for the read-modify-write race) is verified end-to-end.
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp insert_test_case(attrs) do
    project = ProjectsFixtures.project_fixture()
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  defp automation, do: %{name: "Auto", project_id: 1}

  defp event_types(test_case_id) do
    {events, _meta} = Tests.list_test_case_events(test_case_id)
    Enum.map(events, & &1.event_type)
  end

  test "no-ops on empty action list" do
    assert :ok =
             ActionExecutor.execute_actions(
               [],
               automation(),
               %{type: :test_case, id: Ecto.UUID.generate()}
             )
  end

  test "applies change_state and writes the new state to ClickHouse" do
    test_case = insert_test_case(state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "change_state", "state" => "muted"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
    assert "muted" in event_types(test_case.id)
  end

  test "dispatches send_slack to SendSlackAction" do
    entity = %{type: :test_case, id: Ecto.UUID.generate()}

    expect(SendSlackAction, :execute, fn _automation, ^entity, %{"type" => "send_slack"} -> :ok end)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "send_slack", "channel" => "C1", "message" => "hi"}],
               automation(),
               entity
             )
  end

  test "applies add_label flaky as is_flaky: true" do
    test_case = insert_test_case(is_flaky: false)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "add_label", "label" => "flaky"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: true}} = Tests.get_test_case_by_id(test_case.id)
    assert "marked_flaky" in event_types(test_case.id)
  end

  test "applies remove_label flaky as is_flaky: false" do
    test_case = insert_test_case(is_flaky: true)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "remove_label", "label" => "flaky"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false}} = Tests.get_test_case_by_id(test_case.id)
    assert "unmarked_flaky" in event_types(test_case.id)
  end

  test "coalesces add_label flaky + change_state into one update emitting both events" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "muted"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: true, state: "muted"}} = Tests.get_test_case_by_id(test_case.id)

    types = event_types(test_case.id)
    assert "marked_flaky" in types
    assert "muted" in types
  end

  test "coalesces recovery actions (remove_label flaky + change_state enabled) into one update emitting both events" do
    test_case = insert_test_case(is_flaky: true, state: "muted")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "remove_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "enabled"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)

    types = event_types(test_case.id)
    assert "unmarked_flaky" in types
    assert "unmuted" in types
  end

  test "later attribute actions override earlier ones in the merged update" do
    test_case = insert_test_case(is_flaky: false)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "remove_label", "label" => "flaky"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false}} = Tests.get_test_case_by_id(test_case.id)
    refute "marked_flaky" in event_types(test_case.id)
  end

  test "runs slack action after the merged attribute write is visible" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")
    entity = %{type: :test_case, id: test_case.id}
    test_pid = self()

    expect(SendSlackAction, :execute, fn _automation, ^entity, %{"type" => "send_slack"} ->
      assert {:ok, %{is_flaky: true, state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
      send(test_pid, :slack_called)
      :ok
    end)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"},
                 %{"type" => "change_state", "state" => "muted"}
               ],
               automation(),
               entity
             )

    assert_received :slack_called
  end

  test "halts and returns error when the test case does not exist" do
    reject(&SendSlackAction.execute/3)

    assert {:error, :not_found} =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               ],
               automation(),
               %{type: :test_case, id: Ecto.UUID.generate()}
             )
  end

  test "no-ops add_label / remove_label with non-flaky labels" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "slow"},
                 %{"type" => "remove_label", "label" => "slow"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
    assert event_types(test_case.id) == []
  end

  test "silently skips unknown action types without touching the row" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")
    reject(&SendSlackAction.execute/3)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "fly_to_moon"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
    assert event_types(test_case.id) == []
  end
end
