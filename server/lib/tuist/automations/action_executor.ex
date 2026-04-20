defmodule Tuist.Automations.ActionExecutor do
  @moduledoc """
  Dispatches automation actions to their handlers.

  Actions receive an `entity` map with `:type` and `:id` keys,
  e.g. `%{type: :test_case, id: "uuid"}`. This abstraction allows
  the automation engine to operate on different entity types in the
  future (builds, bundles, etc.) without changing the dispatch layer.
  """
  alias Tuist.Automations.Actions.AddLabelAction
  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.Automations.Actions.SendSlackAction

  require Logger

  def execute_actions([], _automation, _entity), do: :ok

  def execute_actions(actions, automation, entity) when is_list(actions) do
    Enum.reduce_while(actions, :ok, fn action, _acc ->
      case execute_action(action, automation, entity) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning("Automation action #{action["type"]} failed for #{entity.type} #{entity.id}: #{inspect(reason)}")

          {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_action(%{"type" => "change_state"} = action, _automation, entity) do
    ChangeStateAction.execute(entity, action)
  end

  defp execute_action(%{"type" => "send_slack"} = action, automation, entity) do
    SendSlackAction.execute(automation, entity, action)
  end

  defp execute_action(%{"type" => "add_label"} = action, _automation, entity) do
    AddLabelAction.execute(entity, action)
  end

  defp execute_action(%{"type" => "remove_label"} = action, _automation, entity) do
    RemoveLabelAction.execute(entity, action)
  end

  defp execute_action(unknown_action, _automation, _entity) do
    Logger.warning("Unknown automation action type: #{inspect(unknown_action)}")
    :ok
  end
end
