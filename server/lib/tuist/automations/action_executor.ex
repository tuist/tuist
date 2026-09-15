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

  Test cases that match or recover together run their actions through
  `execute_grouped_actions/4`. Changes still apply to one test case at a time,
  but each Slack action posts a single message for all of them.
  """
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Tests

  require Logger

  def execute_actions([], _automation, _entity), do: :ok

  def execute_actions(actions, automation, entity) when is_list(actions) do
    with :ok <- execute_actions_without_notifications(actions, automation, entity) do
      actions
      |> Enum.filter(&notification?/1)
      |> run_remaining(automation, entity)
    end
  end

  @doc """
  Runs every action except Slack notifications, which
  `send_grouped_notifications/4` then delivers for a group of test cases.
  """
  def execute_actions_without_notifications(actions, automation, entity) do
    {merged_attrs, remaining_actions} =
      actions
      |> Enum.reject(&notification?/1)
      |> partition_actions(entity)

    with :ok <- apply_merged_attrs(entity, merged_attrs, automation) do
      run_remaining(remaining_actions, automation, entity)
    end
  end

  @doc """
  Runs the actions for test cases that matched or recovered together. Returns
  `{test_case_id, :ok | {:error, reason}}` for each test case, in order.
  """
  def execute_grouped_actions(actions, automation, test_case_ids, phase) when phase in [:trigger, :recovery] do
    results =
      Enum.map(test_case_ids, fn test_case_id ->
        entity = %{type: :test_case, id: test_case_id}
        {test_case_id, execute_actions_without_notifications(actions, automation, entity)}
      end)

    send_grouped_notifications(actions, automation, results, phase)
  end

  @doc """
  Sends each Slack action once for all test cases whose earlier actions
  succeeded. A single test case uses the message template. A failed delivery
  fails every test case in the message, and later actions skip them, as they
  would for a single test case.
  """
  def send_grouped_notifications(actions, automation, results, phase) when phase in [:trigger, :recovery] do
    actions
    |> Enum.filter(&notification?/1)
    |> Enum.reduce(results, fn action, results ->
      notifiable_ids = for {test_case_id, :ok} <- results, do: test_case_id

      case notify(action, automation, notifiable_ids, phase) do
        :ok -> results
        {:error, reason} -> Enum.map(results, &fail_notified_result(&1, reason))
      end
    end)
  end

  defp notify(_action, _automation, [], _phase), do: :ok

  defp notify(action, automation, test_case_ids, phase) do
    result =
      case test_case_ids do
        [test_case_id] -> SendSlackAction.execute(automation, %{type: :test_case, id: test_case_id}, action)
        test_case_ids -> SendSlackAction.execute_group(automation, test_case_ids, action, phase)
      end

    with {:error, reason} <- result do
      Logger.warning(
        "Automation action #{action["type"]} failed for #{length(test_case_ids)} test cases: #{inspect(reason)}"
      )

      result
    end
  end

  defp fail_notified_result({test_case_id, :ok}, reason), do: {test_case_id, {:error, reason}}
  defp fail_notified_result(result, _reason), do: result

  defp notification?(%{"type" => "send_slack"}), do: true
  defp notification?(_action), do: false

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

  defp apply_merged_attrs(_entity, attrs, _automation) when map_size(attrs) == 0, do: :ok

  defp apply_merged_attrs(%{type: :test_case, id: id} = entity, attrs, automation) do
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
