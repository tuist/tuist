defmodule Tuist.Automations.ActionExecutor do
  @moduledoc false
  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Automations.Actions.MarkAsFlakyAction
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Actions.UnmarkAsFlakyAction

  require Logger

  def execute_actions([], _automation, _test_case_id), do: :ok

  def execute_actions(actions, automation, test_case_id) when is_list(actions) do
    Enum.reduce_while(actions, :ok, fn action, _acc ->
      case execute_action(action, automation, test_case_id) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning("Automation action #{action["type"]} failed for test_case #{test_case_id}: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
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

  defp execute_action(unknown_action, _automation, _test_case_id) do
    Logger.warning("Unknown automation action type: #{inspect(unknown_action)}")
    :ok
  end
end
