defmodule Tuist.Automations.ActionExecutor do
  @moduledoc """
  Dispatches automation actions to their handlers.

  Actions receive an `entity` map with `:type` and `:id` keys,
  e.g. `%{type: :test_case, id: "uuid"}`. This abstraction allows
  the automation engine to operate on different entity types in the
  future (builds, bundles, etc.) without changing the dispatch layer.

  When the entity is a `:test_case`, all attribute-mutating actions in the
  list (`add_label`/`remove_label` for the `flaky` label and `change_state`)
  are coalesced into a single `Tests.update_test_case/2` call. Each call
  re-inserts the full row by reading from ClickHouse first, so dispatching
  them sequentially could revert earlier writes when the read had not yet
  observed them.
  """
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Tests

  require Logger

  def execute_actions([], _automation, _entity), do: :ok

  def execute_actions(actions, automation, entity) when is_list(actions) do
    {merged_attrs, remaining_actions} = partition_actions(actions, entity)

    with :ok <- apply_merged_attrs(entity, merged_attrs) do
      run_remaining(remaining_actions, automation, entity)
    end
  end

  defp partition_actions(actions, %{type: :test_case}) do
    actions
    |> Enum.reduce({%{}, []}, fn action, {attrs, others} ->
      case test_case_attr_change(action) do
        {key, value} -> {Map.put(attrs, key, value), others}
        :pass -> {attrs, [action | others]}
      end
    end)
    |> then(fn {attrs, others} -> {attrs, Enum.reverse(others)} end)
  end

  defp partition_actions(actions, _entity), do: {%{}, actions}

  defp test_case_attr_change(%{"type" => "add_label", "label" => "flaky"}), do: {:is_flaky, true}
  defp test_case_attr_change(%{"type" => "remove_label", "label" => "flaky"}), do: {:is_flaky, false}
  defp test_case_attr_change(%{"type" => "change_state", "state" => state}), do: {:state, state}
  defp test_case_attr_change(_), do: :pass

  defp apply_merged_attrs(_entity, attrs) when map_size(attrs) == 0, do: :ok

  defp apply_merged_attrs(%{type: :test_case, id: id} = entity, attrs) do
    case Tests.update_test_case(id, attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Automation test_case attribute update failed for #{entity.type} #{entity.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp run_remaining(actions, automation, entity) do
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

  defp execute_action(%{"type" => "send_slack"} = action, automation, entity) do
    SendSlackAction.execute(automation, entity, action)
  end

  defp execute_action(%{"type" => type}, _automation, _entity) when type in ["add_label", "remove_label"] do
    :ok
  end

  defp execute_action(unknown_action, _automation, _entity) do
    Logger.warning("Unknown automation action type: #{inspect(unknown_action)}")
    :ok
  end
end
