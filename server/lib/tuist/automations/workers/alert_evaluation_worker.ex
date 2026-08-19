defmodule Tuist.Automations.Workers.AlertEvaluationWorker do
  @moduledoc false
  use Oban.Worker, max_attempts: 3, queue: :alert_evaluations

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Holds
  alias Tuist.Automations.Monitors.FlakyTestsMonitor
  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRun

  require Logger

  # Recovery candidates are counted in ClickHouse in batches of this size so the
  # `Array(UUID)` parameter and the run scan stay within the engine's request
  # limits no matter how many tests an alert has quarantined.
  @recovery_candidate_batch_size 500
  @attempts_per_window 3

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 4)

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "project_id" => project_id,
            "cadence_seconds" => cadence_seconds,
            "evaluate_recent_test_case_runs" => true
          }
        } = job
      ) do
    alerts =
      project_id
      |> Automations.list_alerts()
      |> Enum.filter(fn alert ->
        alert.kind == "standard" and alert.enabled and Alert.scoped_evaluation?(alert) and
          Alert.cadence_seconds(alert.cadence) == cadence_seconds and
          trigger_window_supported?(alert)
      end)

    evaluate_recent_test_case_runs_and_execute(alerts, job)
  end

  def perform(%Oban.Job{args: %{"alert_id" => alert_id} = args} = job) do
    case Automations.get_alert(alert_id) do
      {:ok, alert} ->
        cond do
          Alert.manual?(alert) ->
            :ok

          not alert.enabled ->
            :ok

          not trigger_window_supported?(alert) ->
            :ok

          evaluate_recent_test_case_runs?(args) ->
            evaluate_recent_test_case_runs_and_execute(alert, job)

          true ->
            evaluate_and_execute(alert, scoped_test_case_ids(args))
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp trigger_window_supported?(alert) do
    if Alert.trigger_window_supported?(alert) do
      true
    else
      Logger.warning(
        "Skipping automation alert #{alert.id}, including recovery: rolling trigger windows must be between 1 and #{Alert.max_rolling_trigger_window_size()}"
      )

      false
    end
  end

  defp evaluate_recent_test_case_runs_and_execute(%Alert{} = alert, job) do
    if alert.baseline_established_at == nil do
      evaluate_and_execute(alert, nil)
    else
      %{test_case_ids: test_case_ids, cursor: cursor, more?: more?} =
        Automations.recent_test_case_run_changes_for_alert(alert)

      test_case_ids
      |> Automations.scoped_evaluation_ranges()
      |> Enum.each(&evaluate_and_execute(alert, &1))

      {:ok, updated_alert} = Automations.update_alert_scoped_evaluation_cursor(alert, cursor)
      continue_scoped_evaluation(updated_alert, job, more?)
    end
  end

  defp evaluate_recent_test_case_runs_and_execute([], _job), do: :ok

  defp evaluate_recent_test_case_runs_and_execute(alerts, job) when is_list(alerts) do
    {established_alerts, pending_baseline_alerts} =
      Enum.split_with(alerts, &(&1.baseline_established_at != nil))

    Enum.each(pending_baseline_alerts, &evaluate_and_execute(&1, nil))

    if established_alerts == [] do
      :ok
    else
      %{test_case_ids: test_case_ids, cursor: cursor, more?: more?} =
        Automations.recent_test_case_run_changes_for_alerts(established_alerts)

      test_case_ids
      |> Automations.scoped_evaluation_ranges()
      |> Enum.each(&evaluate_alert_group(established_alerts, &1))

      {:ok, _updated_count} = Automations.advance_alert_scoped_evaluation_cursors(established_alerts, cursor)
      continue_scoped_evaluation(hd(established_alerts), job, more?)
    end
  end

  defp continue_scoped_evaluation(_alert, _job, false), do: :ok

  defp continue_scoped_evaluation(_alert, %Oban.Job{id: nil}, true), do: {:snooze, 0}

  defp continue_scoped_evaluation(_alert, %Oban.Job{} = job, true) do
    max_attempts = job.attempt + @attempts_per_window - 1

    case Oban.update_job(job, %{max_attempts: max_attempts}) do
      {:ok, _job} -> {:snooze, 0}
      error -> error
    end
  end

  defp evaluate_recent_test_case_runs?(%{"evaluate_recent_test_case_runs" => true}), do: true
  defp evaluate_recent_test_case_runs?(_args), do: false

  defp evaluate_and_execute(alert, test_case_ids) do
    if alert.baseline_established_at == nil do
      establish_baseline(alert)
    else
      %{triggered: triggered_ids} = evaluate_monitor(alert, test_case_ids)
      execute_evaluation(alert, triggered_ids, test_case_ids)
    end

    :ok
  end

  defp evaluate_alert_group(alerts, test_case_ids) do
    alerts
    |> Enum.group_by(&FlakyTestsMonitor.rolling_group_key/1)
    |> Enum.each(fn
      {nil, alerts} ->
        Enum.each(alerts, &evaluate_and_execute(&1, test_case_ids))

      {_rolling_group_key, [alert]} ->
        evaluate_and_execute(alert, test_case_ids)

      {_rolling_group_key, alerts} ->
        triggered_by_alert_id = FlakyTestsMonitor.evaluate_rolling_alerts(alerts, test_case_ids)

        Enum.each(alerts, fn alert ->
          execute_evaluation(alert, Map.fetch!(triggered_by_alert_id, alert.id), test_case_ids)
        end)
    end)
  end

  defp execute_evaluation(alert, triggered_ids, test_case_ids) do
    triggered_ids = reject_unvalidated_test_cases(alert, triggered_ids)
    run_transitions(alert, triggered_ids, test_case_ids)
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
  defp establish_baseline(alert) do
    Automations.establish_alert_baseline(alert, fn test_case_ids ->
      %{triggered: triggered_ids} = evaluate_monitor(alert, test_case_ids)

      triggered_ids
      |> then(&reject_unvalidated_test_cases(alert, &1))
      |> filter_by_current_state(alert, alert.trigger_config)
    end)
  end

  defp run_transitions(alert, triggered_ids, scoped_test_case_ids) do
    active_events = active_alert_events(alert, scoped_test_case_ids)
    already_triggered_ids = MapSet.new(active_events, & &1.test_case_id)

    newly_triggered =
      triggered_ids
      |> Enum.reject(&MapSet.member?(already_triggered_ids, &1))
      |> filter_by_current_state(alert, alert.trigger_config)

    Enum.each(newly_triggered, fn test_case_id ->
      entity = %{type: :test_case, id: test_case_id}

      case ActionExecutor.execute_actions(alert.trigger_actions, alert, entity) do
        :ok ->
          Automations.create_alert_event(%{
            alert_id: alert.id,
            baseline_generation: alert.baseline_generation,
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
    # fire again) happens for every alert once its condition clears past the
    # dwell window — without it, an alert latches in `triggered` forever and
    # silently stops acting. When recovery is enabled the user's dwell gates
    # re-arming and the undo actions run on top; when it's disabled we re-arm
    # the moment the condition clears (no dwell, no undo) and leave any effect
    # in place until a human clears it. The persisted recovery_config is
    # intentionally ignored on the disabled path because `Alert.changeset`
    # only validates it when recovery is on.
    #
    # The recovery STATE filter only gates whether the undo actions run — it
    # must not gate re-arming. A test whose state was manually changed away
    # from the recovery filter (e.g. someone muted a test the automation had
    # skipped) should be left untouched by recovery, but the alert still has
    # to re-arm once the dwell elapses, or it latches and can never trigger
    # again for that test. So we re-arm every dwell-elapsed candidate and run
    # the actions only on the subset that still matches the filter.
    {to_rearm, actionable_ids} =
      if alert.recovery_enabled do
        elapsed = filter_recovered_candidates(alert, candidates, alert.recovery_config || %{})
        actionable = filter_by_current_state(elapsed, alert, alert.recovery_config)
        {elapsed, MapSet.new(actionable, & &1.test_case_id)}
      else
        {candidates, MapSet.new([])}
      end

    release = release_claims(alert, actionable_ids)

    Enum.each(to_rearm, fn event ->
      entity = %{type: :test_case, id: event.test_case_id}
      actions = recovery_actions_for(alert, event.test_case_id, actionable_ids, release)

      # Run recovery actions BEFORE appending the "recovered" event. If we
      # flipped the order, a failure in the Slack ping / label removal /
      # state reset would leave the rule visually resolved while the user's
      # intended side effects never happened.
      case ActionExecutor.execute_actions(actions, alert, entity) do
        :ok ->
          now = NaiveDateTime.utc_now()

          Automations.create_alert_event(%{
            alert_id: alert.id,
            baseline_generation: alert.baseline_generation,
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

  # Recovery always withdraws the alert's own claim for each actionable test
  # (dual-write: harmless when no claim exists, e.g. baseline-established
  # candidates whose `triggered` event never ran actions). With the holds flag
  # on, the batched re-derivation replaces the absolute `change_state`
  # recovery write and reports which tests actually changed state; with it
  # off, recovery actions keep writing state directly.
  defp release_claims(alert, actionable_ids) do
    if MapSet.size(actionable_ids) == 0 do
      :direct
    else
      Enum.each(actionable_ids, fn test_case_id ->
        case Holds.withdraw_claim(alert, test_case_id) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Alert #{alert.id} claim withdrawal failed for test_case #{test_case_id}: #{inspect(reason)}")
        end
      end)

      if FeatureFlags.test_state_holds_enabled?(alert.project_id) do
        {:ok, %{changed: changed}} =
          Holds.derive_and_apply(alert.project_id, MapSet.to_list(actionable_ids), alert_id: alert.id)

        {:derived, MapSet.new(changed)}
      else
        :direct
      end
    end
  end

  # On the derived path, `change_state` is subsumed by the claim withdrawal
  # and the state-narrating actions announce that release, so they only run
  # when the derived state actually changed — releasing a claim shadowed by
  # another rule must not announce a recovery. Ownership is keyed on the
  # trigger actions: an alert owns claims iff its trigger placed them via
  # `change_state`. Alerts that never place claims (e.g. label-only
  # automations) keep running their recovery actions unconditionally; a
  # claim-owning alert whose release is shadowed still runs its
  # non-narrating label actions but never `send_slack` or `change_state`.
  defp recovery_actions_for(alert, test_case_id, actionable_ids, release) do
    cond do
      not MapSet.member?(actionable_ids, test_case_id) ->
        []

      release == :direct ->
        alert.recovery_actions

      not claim_owning?(alert) ->
        alert.recovery_actions

      true ->
        {:derived, changed} = release

        if MapSet.member?(changed, test_case_id) do
          Enum.reject(alert.recovery_actions, &change_state_action?/1)
        else
          Enum.filter(alert.recovery_actions, &non_narrating_action?/1)
        end
    end
  end

  defp claim_owning?(alert), do: Enum.any?(alert.trigger_actions, &change_state_action?/1)

  defp change_state_action?(%{"type" => "change_state"}), do: true
  defp change_state_action?(_action), do: false

  defp non_narrating_action?(%{"type" => type}), do: type in ["add_label", "remove_label"]
  defp non_narrating_action?(_action), do: false

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

  # A state filter makes an action conditional on the test case's current
  # control-plane state. It lets a skipped-test recovery leave a test alone
  # after someone manually changes it to muted. Omitting the filter preserves
  # the behavior of automations created before this option existed.
  defp filter_by_current_state([], _alert, _config), do: []

  defp filter_by_current_state(items, _alert, config) when not is_map(config), do: items

  defp filter_by_current_state(items, alert, config) do
    case Map.get(config, "states") do
      states when is_list(states) and states != [] ->
        allowed = MapSet.new(states)
        resolved = Tests.get_test_case_states(alert.project_id, Enum.map(items, &test_case_id/1))

        Enum.filter(items, fn item ->
          Map.get(resolved, test_case_id(item), %{state: "enabled"}).state in allowed
        end)

      _ ->
        items
    end
  end

  defp test_case_id(%{test_case_id: test_case_id}), do: test_case_id
  defp test_case_id(test_case_id), do: test_case_id

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
