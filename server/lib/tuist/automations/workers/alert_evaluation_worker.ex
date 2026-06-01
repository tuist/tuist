defmodule Tuist.Automations.Workers.AlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun

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

    triggered_ids = reject_unvalidated_test_cases(alert, triggered_ids)

    if alert.baseline_established_at == nil do
      establish_baseline(alert, triggered_ids)
    else
      run_transitions(alert, triggered_ids, all_ids)
    end

    :ok
  end

  # A test case that has never had a successful, non-flaky run on the project's
  # default branch has not been validated on the trusted branch yet. Examples:
  # a brand-new test still living on its pull-request branch, or a test that
  # merged broken and only ever fails on the default branch. Auto-quarantining
  # such a test would silence it before it was ever proven, so we drop it from
  # the triggered set. It re-enters evaluation naturally once it lands and
  # accrues a passing default-branch run. The check is all-time (not the
  # trigger window) so an established test that passed long ago stays eligible.
  #
  # Recovery is intentionally not filtered: unmuting is always safe.
  defp reject_unvalidated_test_cases(_alert, []), do: []

  defp reject_unvalidated_test_cases(alert, triggered_ids) do
    %{default_branch: default_branch} = Projects.get_project_by_id(alert.project_id)

    validated =
      MapSet.new(
        Tests.test_case_ids_with_successful_default_branch_run(alert.project_id, triggered_ids, default_branch)
      )

    Enum.filter(triggered_ids, &MapSet.member?(validated, &1))
  end

  # First evaluation after the alert was created: every test case currently
  # matching the condition is part of the established state. Record them as
  # `triggered` AlertEvents so subsequent evaluations only fire on
  # transitions, but skip the trigger actions — there's no transition to
  # announce yet, and firing for the entire matching set would spam users.
  defp establish_baseline(alert, triggered_ids) do
    now = NaiveDateTime.utc_now()

    Enum.each(triggered_ids, fn test_case_id ->
      Automations.create_alert_event(%{
        alert_id: alert.id,
        test_case_id: test_case_id,
        status: "triggered",
        triggered_at: now
      })
    end)

    {:ok, _} = Automations.update_alert(alert, %{baseline_established_at: DateTime.utc_now()})
  end

  defp run_transitions(alert, triggered_ids, all_ids) do
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
  end

  defp handle_recovery(alert, currently_triggered_ids, active_events, all_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)
    all_ids_set = MapSet.new(all_ids)
    recovery_config = alert.recovery_config || %{}

    candidates =
      Enum.filter(active_events, fn event ->
        MapSet.member?(all_ids_set, event.test_case_id) and
          not MapSet.member?(currently_triggered_set, event.test_case_id)
      end)

    recovered = filter_recovered_candidates(alert, candidates, recovery_config)

    Enum.each(recovered, fn event ->
      entity = %{type: :test_case, id: event.test_case_id}

      # Run recovery actions BEFORE appending the "recovered" event. If we
      # flipped the order, a failure in the Slack ping / label removal /
      # state reset would leave the rule visually resolved while the user's
      # intended side effects never happened.
      case ActionExecutor.execute_actions(alert.recovery_actions, alert, entity) do
        :ok ->
          now = NaiveDateTime.utc_now()

          Automations.create_alert_event(%{
            alert_id: alert.id,
            test_case_id: event.test_case_id,
            status: "recovered",
            triggered_at: now,
            recovered_at: now
          })

        {:error, reason} ->
          Logger.error(
            "Alert #{alert.id} recovery actions failed for test_case #{event.test_case_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  # In `last_days` mode the recovery cooldown is "wait this long without a
  # re-trigger." In `rolling` mode it's "wait for at least this many new runs
  # of the test case without a re-trigger" — measured against the test_case's
  # own run cadence rather than wall-clock time, which matches what the user
  # picks in the trigger window.
  defp filter_recovered_candidates(_alert, [], _recovery_config), do: []

  defp filter_recovered_candidates(alert, candidates, %{"window_type" => "rolling"} = recovery_config) do
    size = parse_rolling_size(recovery_config["rolling_window_size"])
    counts = batch_runs_since_trigger(alert.project_id, candidates)

    Enum.filter(candidates, fn event ->
      Map.get(counts, event.test_case_id, 0) >= size
    end)
  end

  defp filter_recovered_candidates(_alert, candidates, recovery_config) do
    seconds = parse_window(recovery_config["window"] || "14d")
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)

    Enum.filter(candidates, fn event ->
      NaiveDateTime.before?(event.triggered_at, cutoff)
    end)
  end

  # Each candidate has its own `triggered_at` cutoff, so we can't push the
  # per-candidate filter cleanly into a single SQL `GROUP BY` without a
  # cross-join. Instead, one query pulls every run for the candidate test
  # cases above the global minimum `triggered_at`, and the per-candidate
  # cutoff is applied in Elixir. That trades a small over-fetch (rows
  # between `min(triggered_at)` and each candidate's own `triggered_at`)
  # for one round-trip instead of one-per-candidate.
  #
  # We don't use `FINAL` here for the same reason as in the rolling-window
  # monitor: `test_case_runs` is a ReplacingMergeTree on a hot table where
  # `is_flaky` updates re-insert rows, and `FINAL` multiplies the read by
  # the duplicate factor. A re-inserted run can shift the recovery count by
  # at most one, which is well within the threshold's natural slop.
  defp batch_runs_since_trigger(_project_id, []), do: %{}

  defp batch_runs_since_trigger(project_id, candidates) do
    test_case_ids = Enum.map(candidates, & &1.test_case_id)
    trigger_by_id = Map.new(candidates, &{&1.test_case_id, &1.triggered_at})
    min_triggered_at = candidates |> Enum.map(& &1.triggered_at) |> Enum.min(NaiveDateTime)

    from(r in TestCaseRun,
      where: r.project_id == ^project_id,
      where: r.test_case_id in ^test_case_ids,
      where: r.ran_at > ^min_triggered_at,
      select: {r.test_case_id, r.ran_at}
    )
    |> ClickHouseRepo.all()
    |> Enum.reduce(%{}, fn {test_case_id, ran_at}, acc ->
      case Map.get(trigger_by_id, test_case_id) do
        nil ->
          acc

        triggered_at ->
          if NaiveDateTime.after?(ran_at, triggered_at) do
            Map.update(acc, test_case_id, 1, &(&1 + 1))
          else
            acc
          end
      end
    end)
  end

  defp parse_rolling_size(size) when is_integer(size) and size > 0, do: size
  defp parse_rolling_size(_), do: 100

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

  # Event-driven monitors are dispatched directly from the originating event
  # (see `Tuist.Automations.dispatch_test_case_event/2`), so the scheduled
  # evaluator has nothing to do for them.
  defp evaluate_monitor(%{monitor_type: "test_updated"}) do
    %{triggered: [], all: []}
  end

  defp evaluate_monitor(alert) do
    Logger.warning("Unknown monitor type: #{alert.monitor_type}")
    %{triggered: [], all: []}
  end
end
