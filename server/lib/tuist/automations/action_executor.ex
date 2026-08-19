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

  `change_state` always records a claim in the holds ledger. With the
  `test_state_holds` flag off, the state is still direct-written exactly as
  before (passive dual-write); with it on, the claim plus
  `Holds.derive_and_apply/3` is the state write, and notification actions
  run only when the derived state actually changed.
  """
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Holds
  alias Tuist.FeatureFlags
  alias Tuist.Tests

  require Logger

  def execute_actions([], _automation, _entity), do: :ok

  def execute_actions(actions, automation, entity) when is_list(actions) do
    {merged_attrs, remaining_actions} = partition_actions(actions, entity)

    case apply_merged_attrs(entity, merged_attrs, automation) do
      {:ok, :run_notifications} ->
        run_remaining(remaining_actions, automation, entity)

      {:ok, :skip_notifications} ->
        remaining_actions
        |> Enum.reject(&(&1["type"] == "send_slack"))
        |> run_remaining(automation, entity)

      {:error, reason} ->
        {:error, reason}
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

  defp apply_merged_attrs(_entity, attrs, _automation) when map_size(attrs) == 0, do: {:ok, :run_notifications}

  defp apply_merged_attrs(%{type: :test_case} = entity, attrs, automation) do
    case Map.pop(attrs, :state) do
      {nil, direct_attrs} ->
        with :ok <- update_test_case_attrs(entity, direct_attrs, automation) do
          {:ok, :run_notifications}
        end

      {state, direct_attrs} ->
        apply_state_change(entity, state, direct_attrs, automation)
    end
  end

  # Production callers pass an `Alert` (which has `:id` and `:project_id`);
  # tests/legacy paths sometimes pass a bare map without them. Those cannot
  # own a claim, so they keep the direct state write.
  defp apply_state_change(entity, state, direct_attrs, automation) do
    alert_id = Map.get(automation, :id)
    project_id = Map.get(automation, :project_id)

    cond do
      is_nil(alert_id) or is_nil(project_id) ->
        direct_write_with_state(entity, state, direct_attrs, automation)

      FeatureFlags.test_state_holds_enabled?(project_id) ->
        with :ok <- place_state_claim(automation, entity, state),
             :ok <- update_test_case_attrs(entity, direct_attrs, automation),
             {:ok, %{changed: changed}} <-
               Holds.derive_and_apply(project_id, [entity.id], alert_id: alert_id) do
          {:ok, if(entity.id in changed, do: :run_notifications, else: :skip_notifications)}
        end

      true ->
        # Passive dual-write: the claim is recorded but must never change
        # the direct-write behavior, so its failure only logs.
        _ = place_state_claim(automation, entity, state)
        direct_write_with_state(entity, state, direct_attrs, automation)
    end
  end

  defp direct_write_with_state(entity, state, direct_attrs, automation) do
    with :ok <- update_test_case_attrs(entity, Map.put(direct_attrs, :state, state), automation) do
      {:ok, :run_notifications}
    end
  end

  defp place_state_claim(automation, entity, state) do
    case Holds.place_claim(automation, entity.id, %{state: state}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Automation state claim placement failed for #{entity.type} #{entity.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp update_test_case_attrs(_entity, attrs, _automation) when map_size(attrs) == 0, do: :ok

  defp update_test_case_attrs(%{type: :test_case, id: id} = entity, attrs, automation) do
    # `alert_id` attributes the resulting test_case_event to the firing
    # automation. Production callers always pass an `Alert` (which has
    # `:id`), but tests/legacy paths sometimes pass a bare map without
    # one — fall back to `nil` rather than raising `KeyError`.
    case Tests.update_test_case(id, attrs, alert_id: Map.get(automation, :id)) do
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
