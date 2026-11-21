defmodule Atlas.Engineering.Errors.IssueCoalescer do
  @moduledoc """
  Coalesces per-issue upserts and counter bumps so the ingest hot path
  can run without any synchronous Postgres round-trip.

  Every observation of an event feeds an in-memory accumulator keyed
  by `{project_id, fingerprint}`; every flush interval the accumulator
  is written back to Postgres as a single multi-row
  `INSERT ... ON CONFLICT DO UPDATE`, folding N events per fingerprint
  into one round-trip. This is the pattern that keeps a runaway loop
  from a single noisy issue (the shape of Tuist's real prod incident)
  from serialising every event on the same row lock.

  ## Semantics

  * `record_event/2` calls `observe/4` — a `GenServer.cast` — and
    returns immediately. Callers no longer need to wait on the issue
    upsert.
  * `event_count` becomes eventually consistent: if the coalescer's
    flush fails, that window's bumps are dropped. ClickHouse still
    holds every event, so the true event history is preserved; the
    Postgres counter is a display convenience that trades exactness
    for throughput. `Atlas.Engineering.Errors.DropAlerter` fires on flush failure
    so the discrepancy is never silent.
  * Regression rules match the previous synchronous code:
      * ignored issues stay ignored
      * resolved issues auto-reopen when the observed
        `MAX(event.timestamp)` for the fingerprint is strictly newer
        than `resolved_at`; older backfilled events do not regress
      * unresolved stays unresolved

  ## Regrouping

  When `Atlas.Engineering.Errors.Fingerprint` changes its rules, the same
  events hash to a new fingerprint and so a new issue id. Pass the event's
  `:legacy_fingerprint` to `observe/5`: an issue created under the current
  rules then starts from its legacy issue's status, assignee, resolution and
  first sighting, with the regression rules above applied to it, and alert
  rules see the legacy issue as its previous state. Counts and impacted
  accounts start over; the legacy issue keeps its history and stops growing.

  ## Shutdown

  `terminate/2` runs a final flush so pending observations from the
  last window are not lost across a graceful pod restart.
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo

  require Logger

  @flush_interval_ms :timer.seconds(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records an observation of `event` for the issue identified by
  `{project.id, domain_id, fingerprint}` inside the coalescer. Pass
  `:domain_id` in `opts` when the event came in through a domain-scoped
  Data Source Name; omit it (or pass nil) for the project-level DSN.
  `:legacy_fingerprint` names the issue a new one carries over from (see
  Regrouping). Non-blocking.
  """
  def observe(server, %Project{} = project, fingerprint, %SentryEvent{} = event, opts \\ [])
      when is_binary(fingerprint) do
    domain_id = Keyword.get(opts, :domain_id)
    legacy = Keyword.get(opts, :legacy_fingerprint)
    GenServer.cast(server, {:observe, project, domain_id, fingerprint, legacy, event})
  end

  @doc """
  Forces an immediate flush of the pending accumulator. Only used in
  tests and by the graceful-shutdown callback.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)

    {:ok,
     %{
       # Accumulator keyed by {project_id, domain_id, fingerprint}. A
       # domain_id of nil is the project-level DSN and gets its own
       # bucket, distinct from any domain-scoped observation of the same
       # fingerprint. Value shape documented on `merge_observation/4`.
       accumulator: %{},
       timer: timer,
       interval: interval
     }}
  end

  @impl true
  def handle_cast({:observe, project, domain_id, fingerprint, legacy, event}, state) do
    key = {project.id, domain_id, fingerprint}
    entry = Map.get(state.accumulator, key)
    updated = merge_observation(entry, project, domain_id, fingerprint, legacy, event)
    {:noreply, %{state | accumulator: Map.put(state.accumulator, key, updated)}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def terminate(_reason, %{accumulator: accumulator}) do
    do_flush(accumulator)
  end

  # An accumulator entry holds everything the upsert row needs plus
  # the last-observed environment (used by `Hive.Alerts` rule
  # matching). The most-recently-observed values win for the mutable
  # metadata (title/culprit/level/platform/environment); count is
  # additive; first/last-seen are min/max of every event's timestamp.
  defp merge_observation(nil, project, domain_id, fingerprint, legacy, event) do
    ts = event_timestamp(event)

    %{
      id: Issue.deterministic_id(project.id, domain_id, fingerprint),
      legacy_ids: legacy_ids(project, domain_id, fingerprint, legacy),
      project_id: project.id,
      project_name: project.name,
      project_slack_alert_channel: Map.get(project, :slack_alert_channel),
      domain_id: domain_id,
      fingerprint: fingerprint,
      title: SentryEvent.title(event) |> truncate(500),
      culprit: SentryEvent.culprit(event) |> truncate(500),
      level: String.to_atom(event.level),
      platform: event.platform,
      first_seen: ts,
      last_seen: ts,
      count: 1,
      environment: event.environment
    }
  end

  defp merge_observation(entry, project, domain_id, fingerprint, legacy, event) do
    ts = event_timestamp(event)

    %{
      entry
      | legacy_ids: Enum.uniq(entry.legacy_ids ++ legacy_ids(project, domain_id, fingerprint, legacy)),
        title: SentryEvent.title(event) |> truncate(500),
        culprit: SentryEvent.culprit(event) |> truncate(500),
        level: String.to_atom(event.level),
        platform: event.platform,
        first_seen: min_dt(entry.first_seen, ts),
        last_seen: max_dt(entry.last_seen, ts),
        count: entry.count + 1,
        environment: event.environment || entry.environment
    }
  end

  defp legacy_ids(project, domain_id, fingerprint, legacy) when is_binary(legacy) and legacy != fingerprint,
    do: [Issue.deterministic_id(project.id, domain_id, legacy)]

  defp legacy_ids(_project, _domain_id, _fingerprint, _legacy), do: []

  # Sentry SDKs commonly send timestamps at millisecond precision
  # (e.g. `~U[2026-09-04 09:12:00.000Z]`), but the `errors_issues`
  # Postgres columns are `:utc_datetime_usec` and demand precision=6.
  # `DateTime.truncate/2` doesn't up-scale, so tag the precision
  # explicitly — the raw microsecond value is unchanged, only the
  # precision label is widened.
  defp event_timestamp(%SentryEvent{timestamp: %DateTime{} = ts}), do: force_usec(ts)
  defp event_timestamp(_), do: DateTime.utc_now() |> force_usec()

  defp force_usec(%DateTime{microsecond: {_, 6}} = dt), do: dt

  defp force_usec(%DateTime{microsecond: {value, _}} = dt), do: %{dt | microsecond: {value, 6}}

  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp truncate(nil, _), do: nil
  defp truncate(bin, max) when is_binary(bin), do: String.slice(bin, 0, max)

  defp do_flush(accumulator) when map_size(accumulator) == 0, do: :ok

  defp do_flush(accumulator) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    entries = Map.values(accumulator)
    ids = Enum.map(entries, & &1.id)

    # Snapshot the pre-flush state so `Hive.Alerts.evaluate_error_issue/3`
    # can tell a regression (resolved → unresolved) apart from a plain
    # repeat. New fingerprints show up here as empty structs so the
    # alert evaluator still gets a `before` argument.
    before_by_id = snapshot_before(ids)
    legacy_by_id = legacy_issues(entries)

    rows = Enum.map(entries, &(&1 |> row_for_upsert(now) |> carry_over(Map.get(legacy_by_id, &1.id))))

    try do
      {_inserted, after_issues} =
        Repo.insert_all(
          Issue,
          rows,
          on_conflict: on_conflict_query(),
          conflict_target: [:project_id, :domain_id, :fingerprint],
          returning: true
        )

      evaluate_alerts_for(after_issues, entries, Map.merge(legacy_by_id, before_by_id))
      length(after_issues)
    rescue
      error ->
        total_events = Enum.reduce(entries, 0, &(&2 + &1.count))

        Logger.error(
          "issue_coalescer: flush failed for #{map_size(accumulator)} fingerprint(s) " <>
            "(#{total_events} event bumps dropped): #{Exception.message(error)}"
        )

        # Follow-up: wire alerting for coalescer flush failures.
        Logger.warning(
          "issue_coalescer: alert #{inspect({:issue_coalescer_flush_failed, Exception.message(error)})} fingerprints=#{map_size(accumulator)} events=#{total_events}"
        )

        0
    end
  end

  defp snapshot_before(ids) do
    Issue
    |> where([i], i.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Reconcile every observed origin, including origins first seen in later
  # batches. Suppression requires unanimity; mixed statuses stay unresolved.
  # A deterministic non-null assignee wins, and the earliest sighting survives.
  defp legacy_issues(entries) do
    legacy = snapshot_before(Enum.flat_map(entries, & &1.legacy_ids))

    for entry <- entries,
        entry.legacy_ids != [],
        into: %{} do
      # A newly observed origin has no migrated decision; keep it unresolved
      # and remember its identity just like an existing legacy issue.
      issues =
        Enum.map(entry.legacy_ids, fn id ->
          Map.get(legacy, id, %Issue{id: id, status: :unresolved, first_seen: entry.first_seen})
        end)

      [first | rest] = Enum.sort_by(issues, & &1.id)
      issue = Enum.reduce(rest, first, &merge_legacy/2)
      {entry.id, %{issue | legacy_ids: Enum.map(issues, & &1.id)}}
    end
  end

  defp merge_legacy(a, b) do
    status = if a.status == b.status, do: a.status, else: :unresolved

    %{
      b
      | status: status,
        resolved_at:
          if(status == :resolved && a.resolved_at && b.resolved_at, do: min_dt(a.resolved_at, b.resolved_at)),
        assignee_id: Enum.min(Enum.reject([a.assignee_id, b.assignee_id], &is_nil/1), fn -> nil end),
        first_seen: min_dt(a.first_seen, b.first_seen)
    }
  end

  defp carry_over(row, nil), do: row

  defp carry_over(row, %Issue{} = legacy) do
    regressed? =
      legacy.status == :resolved and not is_nil(legacy.resolved_at) and
        DateTime.after?(row.last_seen, legacy.resolved_at)

    {status, resolved_at} =
      if regressed?, do: {:unresolved, nil}, else: {legacy.status, legacy.resolved_at}

    %{
      row
      | legacy_ids: legacy.legacy_ids,
        status: status,
        resolved_at: resolved_at,
        assignee_id: legacy.assignee_id,
        first_seen: min_dt(row.first_seen, legacy.first_seen)
    }
  end

  defp row_for_upsert(entry, now) do
    %{
      id: entry.id,
      project_id: entry.project_id,
      domain_id: entry.domain_id,
      fingerprint: entry.fingerprint,
      title: entry.title,
      culprit: entry.culprit,
      level: entry.level,
      platform: entry.platform,
      status: :unresolved,
      legacy_ids: [],
      first_seen: entry.first_seen,
      last_seen: entry.last_seen,
      event_count: entry.count,
      resolved_at: nil,
      assignee_id: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  # Hands each touched fingerprint to `Atlas.Engineering.Alerts` for
  # rule matching + cooldown + delivery. Rule dispatch runs off the
  # ingest hot path through an Oban worker so a slow Slack or webhook
  # call cannot block the coalescer flush. Failures here must not fail
  # the flush either — the event is already recorded — so each call is
  # wrapped in a rescue that logs and continues.
  defp evaluate_alerts_for(after_issues, entries, before_by_id) do
    entry_by_id = Map.new(entries, &{&1.id, &1})

    Enum.each(after_issues, fn %Issue{id: id} = issue ->
      entry = Map.fetch!(entry_by_id, id)
      before = Map.get(before_by_id, id) || %{status: nil}

      context = %{environment: Map.get(entry, :environment)}

      try do
        Alerts.evaluate_error_issue(issue, before, context)
      rescue
        err ->
          Logger.warning("issue_coalescer: alerts evaluation failed: #{inspect(err)}")
      end
    end)
  end

  # `insert_all` with ON CONFLICT DO UPDATE. The counter is added to
  # the existing value, first/last-seen are folded via LEAST/GREATEST,
  # the mutable metadata is replaced, and the regression rules are
  # applied via SQL CASE — reopen only if this batch's max timestamp
  # is strictly newer than `resolved_at`.
  # Reconcile only previously unseen origins against the locked current row:
  # replaying known origins would undo subsequent operator decisions. These
  # correlated subqueries stay inside the upsert so replicas cannot race a
  # separate read of the current row's legacy_ids or mutable decisions.
  defp on_conflict_query do
    from(existing in Issue,
      update: [
        set: [
          event_count: fragment("? + EXCLUDED.event_count", existing.event_count),
          first_seen: fragment("LEAST(?, EXCLUDED.first_seen)", existing.first_seen),
          last_seen: fragment("GREATEST(?, EXCLUDED.last_seen)", existing.last_seen),
          title: fragment("EXCLUDED.title"),
          culprit: fragment("EXCLUDED.culprit"),
          level: fragment("EXCLUDED.level"),
          platform: fragment("EXCLUDED.platform"),
          legacy_ids:
            fragment(
              "CASE WHEN ? = '{}'::uuid[] THEN ? ELSE ARRAY(SELECT DISTINCT unnest(? || EXCLUDED.legacy_ids)) END",
              existing.legacy_ids,
              existing.legacy_ids,
              existing.legacy_ids
            ),
          assignee_id:
            fragment(
              """
              CASE WHEN ? <> '{}'::uuid[] AND NOT EXCLUDED.legacy_ids <@ ? THEN
                LEAST(?, (SELECT min(origin.assignee_id::text)::uuid FROM errors_issues origin
                  WHERE origin.id = ANY(EXCLUDED.legacy_ids) AND NOT origin.id = ANY(?)))
              ELSE ? END
              """,
              existing.legacy_ids,
              existing.legacy_ids,
              existing.assignee_id,
              existing.legacy_ids,
              existing.assignee_id
            ),
          status:
            fragment(
              """
              CASE
                WHEN ? <> '{}'::uuid[] AND NOT EXCLUDED.legacy_ids <@ ? THEN
                  CASE WHEN ? = ALL(
                    SELECT COALESCE(origin.status, 'unresolved')
                    FROM unnest(EXCLUDED.legacy_ids) observed(id)
                    LEFT JOIN errors_issues origin ON origin.id = observed.id
                    WHERE NOT observed.id = ANY(?)
                  ) AND (? <> 'resolved' OR
                    GREATEST(?, EXCLUDED.last_seen) <= LEAST(?, (
                      SELECT min(origin.resolved_at) FROM errors_issues origin
                      WHERE origin.id = ANY(EXCLUDED.legacy_ids) AND NOT origin.id = ANY(?)
                    )))
                  THEN ? ELSE 'unresolved' END
                WHEN ? = 'ignored' THEN ?
                WHEN ? = 'resolved' AND ? IS NOT NULL AND EXCLUDED.last_seen > ? THEN ?
                ELSE ?
              END
              """,
              existing.legacy_ids,
              existing.legacy_ids,
              existing.status,
              existing.legacy_ids,
              existing.status,
              existing.last_seen,
              existing.resolved_at,
              existing.legacy_ids,
              existing.status,
              existing.status,
              "ignored",
              existing.status,
              existing.resolved_at,
              existing.resolved_at,
              "unresolved",
              existing.status
            ),
          resolved_at:
            fragment(
              """
              CASE
                WHEN ? <> '{}'::uuid[] AND NOT EXCLUDED.legacy_ids <@ ? THEN
                  CASE WHEN ? = 'resolved' AND 'resolved' = ALL(
                    SELECT COALESCE(origin.status, 'unresolved')
                    FROM unnest(EXCLUDED.legacy_ids) observed(id)
                    LEFT JOIN errors_issues origin ON origin.id = observed.id
                    WHERE NOT observed.id = ANY(?)
                  ) AND GREATEST(?, EXCLUDED.last_seen) <= LEAST(?, (
                    SELECT min(origin.resolved_at) FROM errors_issues origin
                    WHERE origin.id = ANY(EXCLUDED.legacy_ids) AND NOT origin.id = ANY(?)
                  )) THEN LEAST(?, (
                    SELECT min(origin.resolved_at) FROM errors_issues origin
                    WHERE origin.id = ANY(EXCLUDED.legacy_ids) AND NOT origin.id = ANY(?)
                  )) ELSE NULL END
                WHEN ? = 'resolved' AND ? IS NOT NULL AND EXCLUDED.last_seen > ? THEN NULL
                ELSE ?
              END
              """,
              existing.legacy_ids,
              existing.legacy_ids,
              existing.status,
              existing.legacy_ids,
              existing.last_seen,
              existing.resolved_at,
              existing.legacy_ids,
              existing.resolved_at,
              existing.legacy_ids,
              existing.status,
              existing.resolved_at,
              existing.resolved_at,
              existing.resolved_at
            ),
          updated_at: fragment("CURRENT_TIMESTAMP")
        ]
      ]
    )
  end
end
