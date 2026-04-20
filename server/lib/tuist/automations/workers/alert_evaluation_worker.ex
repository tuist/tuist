defmodule Tuist.Automations.Workers.AlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule_id}}) do
    case Automations.get_alert_rule(alert_rule_id) do
      {:ok, alert_rule} ->
        if alert_rule.enabled do
          evaluate_and_execute(alert_rule)
        else
          :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp evaluate_and_execute(alert_rule) do
    %{triggered: triggered_ids, all: all_ids} = evaluate_monitor(alert_rule)
    active_alerts = Automations.list_active_alerts(alert_rule.id)
    already_triggered_ids = MapSet.new(active_alerts, & &1.test_case_id)

    newly_triggered = Enum.reject(triggered_ids, &MapSet.member?(already_triggered_ids, &1))

    Enum.each(newly_triggered, fn test_case_id ->
      entity = %{type: :test_case, id: test_case_id}

      case ActionExecutor.execute_actions(alert_rule.trigger_actions, alert_rule, entity) do
        :ok ->
          Automations.create_alert(%{
            automation_id: alert_rule.id,
            test_case_id: test_case_id,
            status: "triggered",
            triggered_at: NaiveDateTime.utc_now()
          })

        {:error, reason} ->
          Logger.error(
            "Alert rule #{alert_rule.id} trigger actions failed for test_case #{test_case_id}: #{inspect(reason)}"
          )
      end
    end)

    if alert_rule.recovery_enabled do
      handle_recovery(alert_rule, triggered_ids, active_alerts, all_ids)
    end

    :ok
  end

  defp handle_recovery(alert_rule, currently_triggered_ids, active_alerts, all_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)
    all_ids_set = MapSet.new(all_ids)

    recovery_config = alert_rule.recovery_config || %{}
    seconds = parse_window(recovery_config["window"] || "#{recovery_config["days_without_trigger"] || 14}d")
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)

    recovered =
      Enum.filter(active_alerts, fn alert ->
        MapSet.member?(all_ids_set, alert.test_case_id) and
          not MapSet.member?(currently_triggered_set, alert.test_case_id) and
          NaiveDateTime.before?(alert.triggered_at, cutoff)
      end)

    Enum.each(recovered, fn alert ->
      now = NaiveDateTime.utc_now()

      Automations.create_alert(%{
        automation_id: alert_rule.id,
        test_case_id: alert.test_case_id,
        status: "recovered",
        triggered_at: now,
        recovered_at: now
      })

      entity = %{type: :test_case, id: alert.test_case_id}

      case ActionExecutor.execute_actions(alert_rule.recovery_actions, alert_rule, entity) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Alert rule #{alert_rule.id} recovery actions failed for test_case #{alert.test_case_id}: #{inspect(reason)}"
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

  defp evaluate_monitor(%{automation_type: "flakiness_rate"} = alert_rule) do
    FlakyTestsMonitor.evaluate(alert_rule)
  end

  defp evaluate_monitor(%{automation_type: "flaky_run_count"} = alert_rule) do
    FlakyTestsMonitor.evaluate_by_run_count(alert_rule)
  end

  defp evaluate_monitor(alert_rule) do
    Logger.warning("Unknown monitor type: #{alert_rule.automation_type}")
    %{triggered: [], all: []}
  end
end
