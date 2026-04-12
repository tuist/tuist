defmodule Tuist.Automations.Workers.AutomationEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Types.FlakinessRateType

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"automation_id" => automation_id}}) do
    case Automations.get_automation(automation_id) do
      {:ok, automation} ->
        if automation.enabled do
          evaluate_and_execute(automation)
        end

        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp evaluate_and_execute(automation) do
    %{triggered: triggered_ids, all: all_ids} = evaluate_type(automation)
    existing_states = Automations.list_triggered_states(automation.id)
    existing_triggered_ids = MapSet.new(existing_states, & &1.test_case_id)

    newly_triggered = Enum.reject(triggered_ids, &MapSet.member?(existing_triggered_ids, &1))

    Enum.each(newly_triggered, fn test_case_id ->
      ActionExecutor.execute_actions(automation.trigger_actions, automation, test_case_id)

      Automations.insert_automation_state(%{
        automation_id: automation.id,
        test_case_id: test_case_id,
        status: "triggered",
        triggered_at: NaiveDateTime.utc_now()
      })
    end)

    if automation.recovery_enabled do
      handle_recovery(automation, triggered_ids, existing_states, all_ids)
    end
  end

  defp handle_recovery(automation, currently_triggered_ids, existing_states, all_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)
    all_ids_set = MapSet.new(all_ids)

    recovery_config = automation.recovery_config || %{}
    seconds = parse_window(recovery_config["window"] || "#{recovery_config["days_without_trigger"] || 14}d")
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)

    recovered =
      Enum.filter(existing_states, fn state ->
        MapSet.member?(all_ids_set, state.test_case_id) and
          not MapSet.member?(currently_triggered_set, state.test_case_id) and
          NaiveDateTime.before?(state.triggered_at, cutoff)
      end)

    Enum.each(recovered, fn state ->
      ActionExecutor.execute_actions(automation.recovery_actions, automation, state.test_case_id)
      Automations.mark_recovered(automation.id, state.test_case_id)
    end)
  end

  defp parse_window(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, "d"} -> value * 86_400
      {value, "h"} -> value * 3600
      {value, "m"} -> value * 60
      {value, ""} -> value * 86_400
      _ -> 14 * 86_400
    end
  end

  defp parse_window(_), do: 14 * 86_400

  defp evaluate_type(%{automation_type: "flakiness_rate"} = automation) do
    FlakinessRateType.evaluate(automation)
  end

  defp evaluate_type(_automation) do
    %{triggered: [], all: []}
  end
end
