defmodule Tuist.Automations.ActionExecutor do
  @moduledoc false
  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Automations.Actions.MarkAsFlakyAction
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Actions.UnmarkAsFlakyAction

  def execute_actions([], _automation, _test_case_id), do: :ok

  def execute_actions(actions, automation, test_case_id) when is_list(actions) do
    Enum.each(actions, fn action ->
      execute_action(action, automation, test_case_id)
    end)
  end

  defp execute_action(%{"type" => "change_state"} = action, _automation, test_case_id) do
    ChangeStateAction.execute(test_case_id, action)
  end

  defp execute_action(%{"type" => "send_slack"} = action, automation, test_case_id) do
    SendSlackAction.execute(automation, test_case_id, action)
  end

  defp execute_action(%{"type" => "mark_as_flaky"}, _automation, test_case_id) do
    MarkAsFlakyAction.execute(test_case_id)
  end

  defp execute_action(%{"type" => "unmark_as_flaky"}, _automation, test_case_id) do
    UnmarkAsFlakyAction.execute(test_case_id)
  end

  defp execute_action(_unknown_action, _automation, _test_case_id), do: :ok
end
