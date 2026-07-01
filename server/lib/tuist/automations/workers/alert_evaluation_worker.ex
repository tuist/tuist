defmodule Tuist.Automations.Workers.AlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :default

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun

  require Logger

  # Recovery candidates are counted in ClickHouse in batches of this size so the
  # `Array(UUID)` parameter and the run scan stay within the engine's request
  # limits no matter how many tests an alert has quarantined.
  @recovery_candidate_batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => alert_id} = args}) do
    case Automations.get_alert(alert_id) do
      {:ok, alert} ->
        if alert.enabled do
          if evaluate_recent_test_case_runs?(args) do
            evaluate_recent_test_case_runs_and_execute(alert)
          else
            evaluate_and_execute(alert, scoped_test_case_ids(args))
          end
        else
          :ok
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp evaluate_recent_test_case_runs_and_execute(alert) do
    if alert.baseline_established_at == nil do
      evaluate_and_execute(alert, nil)
    else
      %{test_case_ids: test_case_ids, cursor: cursor} = Automations.recent_test_case_run_changes_for_alert(alert)

      test_case_ids
      |> Enum.chunk_every(Automations.scoped_evaluation_chunk_size())
      |> Enum.each(&evaluate_and_execute(alert, &1))

      {:ok, _alert} = Automations.update_alert_scoped_evaluation_cursor(alert, cursor)
    end

    :ok
  end

  defp evaluate_recent_test_case_runs?(%{"evaluate_recent_test_case_runs" => true}), do: true
  defp evaluate_recent_test_case_runs?(_args), do: false

  defp evaluate_and_execute(alert, test_case_ids) do
    if alert.baseline_established_at == nil do
      %{triggered: triggered_ids} = evaluate_monitor(alert, nil)
      triggered_ids = reject_unvalidated_test_cases(alert, triggered_ids)
      establish_baseline(alert, triggered_ids)
    else
      %{triggered: triggered_ids} = evaluate_monitor(alert, test_case_ids)
      triggered_ids = reject_unvalidated_test_cases(alert, triggered_ids)
      run_transitions(alert, triggered_ids, test_case_ids)
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
      MapSet.new(Tests.test_case_ids_with_successful_default_branch_run(alert.project_id, triggered_ids, default_branch))

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

    {:ok, _} = Automations.establish_alert_baseline(alert)
  end

  defp run_transitions(alert, triggered_ids, scoped_test_case_ids) do
    active_events = active_alert_events(alert, scoped_test_case_ids)
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

    # Only metric monitors use this worker's scheduled triggered/recovered
    # ledger. Event-driven (`test_updated`) monitors keep their own ledger via
    # `Automations.dispatch_test_case_event/2` — discrete one-shots with no
    # dwell or recovery — and unknown/legacy monitor types have no evaluator
    # here, so neither participates in recovery. Gating positively also stops a
    # monitor-type change from running recovery over stale `triggered` events.
    if Alert.recovery_ledger?(alert) do
      handle_recovery(alert, triggered_ids, active_events, scoped_test_case_ids)
    end
  end

  defp active_alert_events(alert, nil), do: Automations.list_active_alert_events(alert.id)

  defp active_alert_events(alert, scoped_test_case_ids),
    do: Automations.list_active_alert_events(alert.id, scoped_test_case_ids)

  defp handle_recovery(alert, currently_triggered_ids, active_events, scoped_test_case_ids) do
    currently_triggered_set = MapSet.new(currently_triggered_ids)

    candidates =
      active_events
      |> Enum.reject(&MapSet.member?(currently_triggered_set, &1.test_case_id))
      |> reject_unevaluated_this_tick(scoped_test_case_ids)

    # Re-arming (appending the "recovered" event so the next rising edge can
    # fire again) happens for every alert once its condition clears — without
    # it, an alert latches in `triggered` forever and silently stops acting.
    # When recovery is enabled the user's dwell and undo actions apply; when
    # it's disabled we re-arm the moment the condition clears (no dwell, no
    # undo) and leave any effect in place until a human clears it. The
    # persisted recovery_config is intentionally ignored on the disabled path
    # because `Alert.changeset` only validates it when recovery is on.
    {recovered, recovery_actions} =
      if alert.recovery_enabled do
        {filter_recovered_candidates(alert, candidates, alert.recovery_config || %{}), alert.recovery_actions}
      else
        {candidates, []}
      end

    Enum.each(recovered, fn event ->
      entity = %{type: :test_case, id: event.test_case_id}

      # Run recovery actions BEFORE appending the "recovered" event. If we
      # flipped the order, a failure in the Slack ping / label removal /
      # state reset would leave the rule visually resolved while the user's
      # intended side effects never happened.
      case ActionExecutor.execute_actions(recovery_actions, alert, entity) do
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

  # A scoped evaluation only re-checked `scoped_test_case_ids`, so a triggered
  # test case outside that set wasn't measured this tick — leave its event
  # alone rather than treating "absent from the triggered set" as "cleared." A
  # full evaluation (nil) re-checks every test case, so every active event is
  # fair game.
  defp reject_unevaluated_this_tick(candidates, nil), do: candidates

  defp reject_unevaluated_this_tick(candidates, scoped_test_case_ids) do
    evaluated = MapSet.new(scoped_test_case_ids)
    Enum.filter(candidates, &MapSet.member?(evaluated, &1.test_case_id))
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

  # Counts, per candidate, the runs that followed its own `triggered_at`. The
  # count is aggregated inside ClickHouse (one row per candidate) rather than
  # streaming every run back to be tallied in Elixir — a long-muted,
  # high-frequency test would otherwise return millions of rows. Candidates are
  # processed in batches because a bare `test_case_id in ^ids` over a large
  # quarantined set overflows ClickHouse's request limits (the same reason
  # `Tests.test_case_ids_with_successful_default_branch_run` batches with an
  # `Array(UUID)` parameter); each batch bounds the parameter and the scan.
  #
  # We don't use `FINAL` here for the same reason as in the rolling-window
  # monitor: `test_case_runs` is a ReplacingMergeTree on a hot table where
  # `is_flaky` updates re-insert rows, and `FINAL` multiplies the read by
  # the duplicate factor. A re-inserted run can shift the recovery count by
  # at most one, which is well within the threshold's natural slop.
  defp batch_runs_since_trigger(_project_id, []), do: %{}

  defp batch_runs_since_trigger(project_id, candidates) do
    candidates
    |> Enum.chunk_every(@recovery_candidate_batch_size)
    |> Enum.reduce(%{}, fn batch, acc ->
      Map.merge(acc, batch_run_counts(project_id, batch))
    end)
  end

  # `cutoffs` is positionally aligned with `test_case_ids`, so for each run row
  # `arrayElement(cutoffs, indexOf(test_case_ids, test_case_id))` resolves the
  # candidate's own `triggered_at` (in microseconds) and the count only includes
  # runs strictly after it. The `ran_at > min_triggered_at` clause narrows the
  # primary-key scan to runs after the earliest trigger in the batch.
  defp batch_run_counts(project_id, batch) do
    test_case_ids = Enum.map(batch, & &1.test_case_id)
    cutoffs = Enum.map(batch, &triggered_at_micros(&1.triggered_at))
    min_triggered_at = batch |> Enum.map(& &1.triggered_at) |> Enum.min(NaiveDateTime)

    from(r in TestCaseRun,
      where: r.project_id == ^project_id,
      where: fragment("? IN (?)", r.test_case_id, type(^test_case_ids, {:array, Ecto.UUID})),
      where: r.ran_at > ^min_triggered_at,
      where:
        fragment(
          "toUnixTimestamp64Micro(?) > arrayElement(?, indexOf(?, ?))",
          r.ran_at,
          type(^cutoffs, {:array, :integer}),
          type(^test_case_ids, {:array, Ecto.UUID}),
          r.test_case_id
        ),
      group_by: r.test_case_id,
      select: {r.test_case_id, fragment("count(*)")}
    )
    |> ClickHouseRepo.all(multipart: true)
    |> Map.new()
  end

  defp triggered_at_micros(%NaiveDateTime{} = triggered_at) do
    triggered_at
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:microsecond)
  end

  defp parse_rolling_size(size) when is_integer(size) and size > 0, do: min(size, Alert.max_rolling_window_size())
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

  defp evaluate_monitor(%{monitor_type: "flakiness_rate"} = alert, nil) do
    FlakyTestsMonitor.evaluate(alert)
  end

  defp evaluate_monitor(%{monitor_type: "flakiness_rate"} = alert, test_case_ids) do
    FlakyTestsMonitor.evaluate(alert, test_case_ids)
  end

  defp evaluate_monitor(%{monitor_type: "flaky_run_count"} = alert, nil) do
    FlakyTestsMonitor.evaluate_by_run_count(alert)
  end

  defp evaluate_monitor(%{monitor_type: "flaky_run_count"} = alert, test_case_ids) do
    FlakyTestsMonitor.evaluate_by_run_count(alert, test_case_ids)
  end

  defp evaluate_monitor(%{monitor_type: "reliability_rate"} = alert, nil) do
    FlakyTestsMonitor.evaluate_by_reliability_rate(alert)
  end

  defp evaluate_monitor(%{monitor_type: "reliability_rate"} = alert, test_case_ids) do
    FlakyTestsMonitor.evaluate_by_reliability_rate(alert, test_case_ids)
  end

  # Event-driven monitors are dispatched directly from the originating event
  # (see `Tuist.Automations.dispatch_test_case_event/2`), so the scheduled
  # evaluator has nothing to do for them.
  defp evaluate_monitor(%{monitor_type: "test_updated"}, _test_case_ids) do
    %{triggered: []}
  end

  defp evaluate_monitor(alert, _test_case_ids) do
    Logger.warning("Unknown monitor type: #{alert.monitor_type}")
    %{triggered: []}
  end

  defp scoped_test_case_ids(%{"test_case_ids" => test_case_ids}) when is_list(test_case_ids) do
    test_case_ids
    |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
    |> Enum.uniq()
  end

  defp scoped_test_case_ids(_args), do: nil
end
