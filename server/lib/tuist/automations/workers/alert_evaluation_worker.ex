defmodule Tuist.Automations.Workers.AlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.Tests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => alert_id}}) do
    case Automations.get_alert(alert_id) do
      {:ok, alert} ->
        if alert.enabled do
          evaluate_and_execute(alert)
        else
          :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp evaluate_and_execute(alert) do
    %{triggered: triggered_ids, all: all_ids} = evaluate_monitor(alert)
    active_events = Automations.list_active_alert_events(alert.id)
    already_triggered_ids = MapSet.new(active_events, & &1.test_case_id)

    newly_triggered = Enum.reject(triggered_ids, &MapSet.member?(already_triggered_ids, &1))

    Enum.each(newly_triggered, fn test_case_id ->
      entity = %{type: :test_case, id: test_case_id}

      case ActionExecutor.execute_actions(alert.trigger_actions, alert, entity) do
        :ok ->
          Automations.create_alert_event(%{
            alert_id: alert.id,
            test_case_id: test_case_id,
            status: "triggered",
            triggered_at: NaiveDateTime.utc_now()
          })

        {:error, reason} ->
          Logger.error("Alert #{alert.id} trigger actions failed for test_case #{test_case_id}: #{inspect(reason)}")
      end
    end)

    if alert.recovery_enabled do
      handle_recovery(alert, triggered_ids, active_events, all_ids)
    end

    :ok
  end

  defp handle_recovery(alert, currently_triggered_ids, active_events, all_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)
    all_ids_set = MapSet.new(all_ids)

    recovery_config = alert.recovery_config || %{}
    seconds = parse_window(recovery_config["window"] || "#{recovery_config["days_without_trigger"] || 14}d")
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)

    recovered_ids =
      active_events
      |> Enum.filter(fn event ->
        MapSet.member?(all_ids_set, event.test_case_id) and
          not MapSet.member?(currently_triggered_set, event.test_case_id) and
          NaiveDateTime.before?(event.triggered_at, cutoff)
      end)
      |> Enum.map(& &1.test_case_id)

    Enum.each(recovered_ids, &recover_test_case(alert, &1))

    recover_orphaned_flaky_test_cases(alert, currently_triggered_set, active_events, recovered_ids)
  end

  # Tests get marked `is_flaky = true` outside this alert's tracking: manually
  # via UI/API, by a previous automation that has since been deleted or
  # reconfigured, or by an earlier evaluation that lost its event due to the
  # ClickHouse read-modify-write race fixed in `ActionExecutor`. Without this
  # path they would stay flagged forever, because recovery walks
  # `active_events` only.
  defp recover_orphaned_flaky_test_cases(alert, currently_triggered_set, active_events, already_recovered_ids) do
    tracked_ids =
      active_events
      |> MapSet.new(& &1.test_case_id)
      |> MapSet.union(MapSet.new(already_recovered_ids))

    alert.project_id
    |> Tests.list_flagged_flaky_test_case_ids()
    |> Enum.reject(fn id ->
      MapSet.member?(tracked_ids, id) or MapSet.member?(currently_triggered_set, id)
    end)
    |> Enum.each(&recover_test_case(alert, &1))
  end

  defp recover_test_case(alert, test_case_id) do
    entity = %{type: :test_case, id: test_case_id}

    # Run recovery actions BEFORE appending the "recovered" event. If we
    # flipped the order, a failure in the Slack ping / label removal /
    # state reset would leave the rule visually resolved while the user's
    # intended side effects never happened.
    case ActionExecutor.execute_actions(alert.recovery_actions, alert, entity) do
      :ok ->
        now = NaiveDateTime.utc_now()

        Automations.create_alert_event(%{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: "recovered",
          triggered_at: now,
          recovered_at: now
        })

      {:error, reason} ->
        Logger.error("Alert #{alert.id} recovery actions failed for test_case #{test_case_id}: #{inspect(reason)}")
    end
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

  defp evaluate_monitor(%{monitor_type: "flakiness_rate"} = alert) do
    FlakyTestsMonitor.evaluate(alert)
  end

  defp evaluate_monitor(%{monitor_type: "flaky_run_count"} = alert) do
    FlakyTestsMonitor.evaluate_by_run_count(alert)
  end

  defp evaluate_monitor(alert) do
    Logger.warning("Unknown monitor type: #{alert.monitor_type}")
    %{triggered: [], all: []}
  end
end
