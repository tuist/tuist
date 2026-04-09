defmodule Tuist.Automations.ActionExecutor do
  @moduledoc false
  alias Tuist.Automations.Actions.ChangeStateAction

  def execute_actions([], _test_case_id), do: :ok

  def execute_actions(actions, test_case_id) when is_list(actions) do
    Enum.each(actions, fn action ->
      execute_action(action, test_case_id)
    end)
  end

  defp execute_action(%{"type" => "change_state"} = action, test_case_id) do
    ChangeStateAction.execute(test_case_id, action)
  end

  defp execute_action(_unknown_action, _test_case_id), do: :ok
end
