defmodule Tuist.Automations.ActionExecutorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Actions.AddLabelAction
  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.Automations.Actions.SendSlackAction

  setup do
    entity = %{type: :test_case, id: Ecto.UUID.generate()}
    %{automation: %{name: "Auto", project_id: 1}, entity: entity}
  end

  test "no-ops on empty action list", %{automation: automation, entity: entity} do
    assert :ok = ActionExecutor.execute_actions([], automation, entity)
  end

  test "dispatches change_state to ChangeStateAction", %{automation: automation, entity: entity} do
    expect(ChangeStateAction, :execute, fn ^entity, %{"state" => "muted"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "change_state", "state" => "muted"}],
      automation,
      entity
    )
  end

  test "dispatches send_slack to SendSlackAction", %{automation: automation, entity: entity} do
    expect(SendSlackAction, :execute, fn ^automation, ^entity, %{"type" => "send_slack"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "send_slack", "channel" => "C1", "message" => "hi"}],
      automation,
      entity
    )
  end

  test "dispatches add_label to AddLabelAction", %{automation: automation, entity: entity} do
    expect(AddLabelAction, :execute, fn ^entity, %{"label" => "flaky"} -> :ok end)
    ActionExecutor.execute_actions([%{"type" => "add_label", "label" => "flaky"}], automation, entity)
  end

  test "dispatches remove_label to RemoveLabelAction", %{automation: automation, entity: entity} do
    expect(RemoveLabelAction, :execute, fn ^entity, %{"label" => "flaky"} -> :ok end)
    ActionExecutor.execute_actions([%{"type" => "remove_label", "label" => "flaky"}], automation, entity)
  end

  test "executes multiple actions in order", %{automation: automation, entity: entity} do
    expect(AddLabelAction, :execute, fn ^entity, %{"label" => "flaky"} -> :ok end)
    expect(ChangeStateAction, :execute, fn ^entity, %{"state" => "muted"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "add_label", "label" => "flaky"}, %{"type" => "change_state", "state" => "muted"}],
      automation,
      entity
    )
  end

  test "silently skips unknown action types", %{automation: automation, entity: entity} do
    reject(&ChangeStateAction.execute/2)
    reject(&SendSlackAction.execute/3)
    reject(&AddLabelAction.execute/2)
    reject(&RemoveLabelAction.execute/2)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "fly_to_moon"}],
               automation,
               entity
             )
  end
end
