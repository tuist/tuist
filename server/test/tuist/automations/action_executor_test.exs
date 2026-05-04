defmodule Tuist.Automations.ActionExecutorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Tests

  setup do
    entity = %{type: :test_case, id: Ecto.UUID.generate()}
    %{automation: %{name: "Auto", project_id: 1}, entity: entity}
  end

  test "no-ops on empty action list", %{automation: automation, entity: entity} do
    reject(&Tests.update_test_case/2)
    assert :ok = ActionExecutor.execute_actions([], automation, entity)
  end

  test "applies change_state through a single update_test_case call", %{
    automation: automation,
    entity: %{id: id} = entity
  } do
    expect(Tests, :update_test_case, fn ^id, %{state: "muted"} -> {:ok, %{}} end)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "change_state", "state" => "muted"}],
               automation,
               entity
             )
  end

  test "dispatches send_slack to SendSlackAction", %{automation: automation, entity: entity} do
    reject(&Tests.update_test_case/2)
    expect(SendSlackAction, :execute, fn ^automation, ^entity, %{"type" => "send_slack"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "send_slack", "channel" => "C1", "message" => "hi"}],
      automation,
      entity
    )
  end

  test "applies add_label flaky as is_flaky: true", %{automation: automation, entity: %{id: id} = entity} do
    expect(Tests, :update_test_case, fn ^id, %{is_flaky: true} -> {:ok, %{}} end)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "add_label", "label" => "flaky"}],
               automation,
               entity
             )
  end

  test "applies remove_label flaky as is_flaky: false", %{automation: automation, entity: %{id: id} = entity} do
    expect(Tests, :update_test_case, fn ^id, %{is_flaky: false} -> {:ok, %{}} end)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "remove_label", "label" => "flaky"}],
               automation,
               entity
             )
  end

  test "coalesces add_label flaky and change_state into one update_test_case call", %{
    automation: automation,
    entity: %{id: id} = entity
  } do
    expect(Tests, :update_test_case, fn ^id, attrs ->
      assert attrs == %{is_flaky: true, state: "muted"}
      {:ok, %{}}
    end)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "muted"}
               ],
               automation,
               entity
             )
  end

  test "coalesces recovery actions (remove_label flaky + change_state enabled) into one call", %{
    automation: automation,
    entity: %{id: id} = entity
  } do
    expect(Tests, :update_test_case, fn ^id, attrs ->
      assert attrs == %{is_flaky: false, state: "enabled"}
      {:ok, %{}}
    end)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "remove_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "enabled"}
               ],
               automation,
               entity
             )
  end

  test "later attribute actions override earlier ones in the merged update", %{
    automation: automation,
    entity: %{id: id} = entity
  } do
    expect(Tests, :update_test_case, fn ^id, attrs ->
      assert attrs == %{is_flaky: false}
      {:ok, %{}}
    end)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "remove_label", "label" => "flaky"}
               ],
               automation,
               entity
             )
  end

  test "runs slack action after the merged attribute update", %{
    automation: automation,
    entity: %{id: id} = entity
  } do
    test_pid = self()

    expect(Tests, :update_test_case, fn ^id, %{is_flaky: true, state: "muted"} ->
      send(test_pid, :update_called)
      {:ok, %{}}
    end)

    expect(SendSlackAction, :execute, fn ^automation, ^entity, %{"type" => "send_slack"} ->
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
               automation,
               entity
             )

    assert_received :update_called
    assert_received :slack_called
  end

  test "halts and returns error when update_test_case fails", %{automation: automation, entity: %{id: id} = entity} do
    expect(Tests, :update_test_case, fn ^id, _attrs -> {:error, :not_found} end)
    reject(&SendSlackAction.execute/3)

    assert {:error, :not_found} =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               ],
               automation,
               entity
             )
  end

  test "no-ops add_label / remove_label with non-flaky labels", %{automation: automation, entity: entity} do
    reject(&Tests.update_test_case/2)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "slow"},
                 %{"type" => "remove_label", "label" => "slow"}
               ],
               automation,
               entity
             )
  end

  test "silently skips unknown action types", %{automation: automation, entity: entity} do
    reject(&Tests.update_test_case/2)
    reject(&SendSlackAction.execute/3)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "fly_to_moon"}],
               automation,
               entity
             )
  end
end
