defmodule Tuist.Automations.ActionExecutorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Actions.AddLabelAction
  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.Automations.Actions.SendSlackAction

  setup do
    %{automation: %{name: "Auto", project_id: 1}, test_case_id: Ecto.UUID.generate()}
  end

  test "no-ops on empty action list", %{automation: automation, test_case_id: tc_id} do
    assert :ok = ActionExecutor.execute_actions([], automation, tc_id)
  end

  test "dispatches change_state to ChangeStateAction", %{automation: automation, test_case_id: tc_id} do
    expect(ChangeStateAction, :execute, fn ^tc_id, %{"state" => "muted"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "change_state", "state" => "muted"}],
      automation,
      tc_id
    )
  end

  test "dispatches send_slack to SendSlackAction", %{automation: automation, test_case_id: tc_id} do
    expect(SendSlackAction, :execute, fn ^automation, ^tc_id, %{"type" => "send_slack"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "send_slack", "channel" => "C1", "message" => "hi"}],
      automation,
      tc_id
    )
  end

  test "dispatches add_label to AddLabelAction", %{automation: automation, test_case_id: tc_id} do
    expect(AddLabelAction, :execute, fn ^tc_id, %{"label" => "flaky"} -> :ok end)
    ActionExecutor.execute_actions([%{"type" => "add_label", "label" => "flaky"}], automation, tc_id)
  end

  test "dispatches remove_label to RemoveLabelAction", %{automation: automation, test_case_id: tc_id} do
    expect(RemoveLabelAction, :execute, fn ^tc_id, %{"label" => "flaky"} -> :ok end)
    ActionExecutor.execute_actions([%{"type" => "remove_label", "label" => "flaky"}], automation, tc_id)
  end

  test "executes multiple actions in order", %{automation: automation, test_case_id: tc_id} do
    expect(AddLabelAction, :execute, fn ^tc_id, %{"label" => "flaky"} -> :ok end)
    expect(ChangeStateAction, :execute, fn ^tc_id, %{"state" => "muted"} -> :ok end)

    ActionExecutor.execute_actions(
      [%{"type" => "add_label", "label" => "flaky"}, %{"type" => "change_state", "state" => "muted"}],
      automation,
      tc_id
    )
  end

  test "silently skips unknown action types", %{automation: automation, test_case_id: tc_id} do
    reject(&ChangeStateAction.execute/2)
    reject(&SendSlackAction.execute/3)
    reject(&AddLabelAction.execute/2)
    reject(&RemoveLabelAction.execute/2)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "fly_to_moon"}],
               automation,
               tc_id
             )
  end
end
