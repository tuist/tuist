defmodule Tuist.Automations.Workers.AutomationEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"automation_id" => automation_id}}) do
    case Automations.get_automation(automation_id) do
      {:ok, automation} ->
        if automation.enabled do
          evaluate_and_execute(automation)
        else
          :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp evaluate_and_execute(automation) do
    %{triggered: triggered_ids, all: all_ids} = evaluate_monitor(automation)
    active_alerts = Automations.list_active_alerts(automation.id)
    already_triggered_ids = MapSet.new(active_alerts, & &1.test_case_id)

    newly_triggered = Enum.reject(triggered_ids, &MapSet.member?(already_triggered_ids, &1))

    Enum.each(newly_triggered, fn test_case_id ->
      entity = %{type: :test_case, id: test_case_id}

      case ActionExecutor.execute_actions(automation.trigger_actions, automation, entity) do
        :ok ->
          Automations.create_alert(%{
            automation_id: automation.id,
            test_case_id: test_case_id,
            status: "triggered",
            triggered_at: NaiveDateTime.utc_now()
          })

        {:error, reason} ->
          Logger.error(
            "Automation #{automation.id} trigger actions failed for test_case #{test_case_id}: #{inspect(reason)}"
          )
      end
    end)

    if automation.recovery_enabled do
      handle_recovery(automation, triggered_ids, active_alerts, all_ids)
    end

    :ok
  end

  defp handle_recovery(automation, currently_triggered_ids, active_alerts, all_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)
    all_ids_set = MapSet.new(all_ids)

    recovery_config = automation.recovery_config || %{}
    seconds = parse_window(recovery_config["window"] || "#{recovery_config["days_without_trigger"] || 14}d")
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)

    recovered =
      Enum.filter(active_alerts, fn alert ->
        MapSet.member?(all_ids_set, alert.test_case_id) and
          not MapSet.member?(currently_triggered_set, alert.test_case_id) and
          NaiveDateTime.before?(alert.triggered_at, cutoff)
      end)

    Enum.each(recovered, fn alert ->
      Automations.resolve_alert(automation.id, alert.test_case_id)
      entity = %{type: :test_case, id: alert.test_case_id}

      case ActionExecutor.execute_actions(automation.recovery_actions, automation, entity) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Automation #{automation.id} recovery actions failed for test_case #{alert.test_case_id}: #{inspect(reason)}"
          )
      end
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

  defp evaluate_monitor(%{automation_type: "flakiness_rate"} = automation) do
    FlakyTestsMonitor.evaluate(automation)
  end

  defp evaluate_monitor(%{automation_type: "flaky_run_count"} = automation) do
    FlakyTestsMonitor.evaluate_by_run_count(automation)
  end

  defp evaluate_monitor(automation) do
    Logger.warning("Unknown monitor type: #{automation.automation_type}")
    %{triggered: [], all: []}
  end
end
