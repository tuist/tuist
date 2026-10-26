defmodule Tuist.Automations.Execution do
  @moduledoc """
  Durable metric automation execution. PostgreSQL owns evaluation checkpoints
  and pending transitions; ClickHouse remains the source of measurements and
  the destination for history. Enable only after all replicas support this path.
  """
  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Execution.Evaluation
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.Automations.Workers.EvaluationPageWorker
  alias Tuist.Automations.Workers.TransitionWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Tests.TestCaseRun

  @page_size 200
  @revision_fields ~w(enabled monitor_type trigger_config trigger_actions recovery_enabled recovery_config recovery_actions baseline_generation event_generation execution_revision)a

  def revision(alert) do
    alert
    |> Map.take(@revision_fields)
    |> Map.update!(:trigger_config, &Map.delete(&1, "apply_actions_to_existing_matches"))
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  # Administrative cutover. Locking Oban's table excludes the claim/activation
  # race. Pending jobs are safe: compatible workers re-read the alert on entry.
  # Old binaries must have been drained before invoking this function.
  def enable(alert_id) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL lock_timeout = '2s'")
      alert = locked_alert(alert_id)
      Repo.query!("LOCK TABLE oban_jobs IN SHARE ROW EXCLUSIVE MODE")

      executing =
        from(j in Oban.Job,
          where: j.worker == "Tuist.Automations.Workers.AlertEvaluationWorker" and j.state == "executing",
          where:
            fragment(
              "?->>'alert_id' = ? OR ?->>'project_id' = ?",
              j.args,
              ^alert.id,
              j.args,
              ^to_string(alert.project_id)
            )
        )

      if Repo.exists?(executing), do: Repo.rollback(:evaluation_in_progress)
      if !Alert.recovery_ledger?(alert), do: Repo.rollback(:unsupported_monitor)
      alert |> Ecto.Changeset.change(durable_execution: true) |> Repo.update!()
    end)
  end

  def schedule(%Alert{id: id}, args \\ %{}) do
    {:ok, :ok} =
      Repo.transaction(fn ->
        alert = locked_alert(id)
        if eligible?(alert), do: schedule_locked(alert, args)
        :ok
      end)

    :ok
  end

  defp schedule_locked(alert, args) do
    current = Repo.one(from(r in Evaluation, where: r.alert_id == ^alert.id and r.state == "running"))

    if current && current.revision == revision(alert) do
      :ok
    else
      if current, do: update!(current, state: "cancelled")
      now = DateTime.utc_now()
      baseline = is_nil(alert.baseline_established_at)
      scope = scope(alert, args, now, baseline)

      run =
        Repo.insert!(%Evaluation{
          alert_id: alert.id,
          revision: revision(alert),
          evaluated_at: now,
          baseline: baseline,
          scope: scope
        })

      enqueue_page(run)
    end
  end

  defp scope(alert, args, now, false) do
    cond do
      is_list(args["test_case_ids"]) ->
        ids = args["test_case_ids"] |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1))) |> Enum.uniq() |> Enum.sort()
        %{"ids" => ids}

      args["evaluate_recent_test_case_runs"] == true ->
        cursor = alert.last_scoped_evaluation_inserted_at || now
        lookback = max(div(Environment.clickhouse_flush_interval_ms(), 1000) + 1, 10)
        finish = Enum.min([DateTime.add(cursor, 900, :second), now], DateTime)

        %{
          "start" => DateTime.to_iso8601(DateTime.add(cursor, -lookback, :second)),
          "end" => DateTime.to_iso8601(finish),
          "more" => DateTime.before?(finish, now)
        }

      true ->
        %{}
    end
  end

  defp scope(alert, _args, _now, true), do: %{"apply_existing" => Alert.apply_actions_to_existing_matches?(alert)}

  # Internal jobs derive tenant context from the persisted run, never from a
  # client-supplied project argument.
  def evaluate_page(run_id) do
    case Repo.get(Evaluation, run_id) do
      %Evaluation{state: "running"} = run ->
        alert = Repo.get!(Alert, run.alert_id)

        if eligible?(alert) and revision(alert) == run.revision do
          alert = %{alert | evaluation_at: run.evaluated_at}
          {ids, cursor} = page(alert, run)
          legacy = Automations.list_active_alert_events(alert, ids)
          active = active_events(alert, ids, legacy)
          proposals = proposals(alert, run, ids, active)
          commit_page(run, ids, cursor, legacy, proposals)
        else
          update!(run, state: "cancelled")
        end

        :ok

      _ ->
        :ok
    end
  end

  defp page(_alert, %Evaluation{scope: %{"ids" => ids}, cursor: cursor}) do
    offset = if cursor, do: cursor["offset"], else: 0
    page = Enum.slice(ids, offset, @page_size)
    {page, %{"offset" => offset + length(page)}}
  end

  defp page(alert, %Evaluation{scope: %{"start" => start, "end" => finish}, cursor: cursor}) do
    start = naive(start)
    finish = naive(finish)

    query =
      from(r in {"test_case_runs_by_inserted_at", TestCaseRun},
        where: r.project_id == ^alert.project_id and not is_nil(r.test_case_id),
        where: r.inserted_at >= ^start and r.inserted_at < ^finish,
        group_by: r.test_case_id,
        order_by: r.test_case_id,
        limit: @page_size,
        select: r.test_case_id
      )

    query = if cursor, do: where(query, [r], r.test_case_id > ^cursor["id"]), else: query
    ids = ClickHouseRepo.all(query)
    {ids, %{"id" => List.last(ids)}}
  end

  defp page(alert, run) do
    cases = Automations.list_alert_baseline_test_case_page(alert.project_id, run.cursor, @page_size)

    cursor =
      case List.last(cases) do
        nil -> nil
        last -> Map.new(last, fn {key, value} -> {Atom.to_string(key), value} end)
      end

    {Enum.map(cases, & &1.id), cursor}
  end

  defp proposals(_alert, _run, [], _active), do: []

  defp proposals(alert, %Evaluation{baseline: true, scope: scope, id: run_id}, ids, _active) do
    actions = if scope["apply_existing"], do: alert.trigger_actions, else: []

    alert
    |> Automations.matching_test_case_ids(ids)
    |> Enum.map(
      &%{
        test_case_id: &1,
        status: "triggered",
        actions: actions,
        force: scope["apply_existing"] == true,
        source_id: run_id
      }
    )
  end

  defp proposals(alert, _run, ids, active), do: AlertEvaluationWorker.plan_transitions(alert, ids, active)

  def active_events(alert, ids, legacy) do
    states = alert |> states(ids) |> Repo.all() |> Map.new(&{&1.test_case_id, &1})
    legacy = Map.new(legacy, &{&1.test_case_id, &1})

    Enum.flat_map(ids, fn id ->
      case Map.get(states, id) do
        %TestState{status: "triggered", triggered_at: at} -> [%{test_case_id: id, triggered_at: DateTime.to_naive(at)}]
        %TestState{} -> []
        nil -> List.wrap(Map.get(legacy, id))
      end
    end)
  end

  defp commit_page(run, ids, cursor, legacy, proposals) do
    {:ok, _} =
      Repo.transaction(fn ->
        alert = locked_alert(run.alert_id)
        current = Repo.get!(Evaluation, run.id)

        cond do
          current.state != "running" or current.cursor != run.cursor ->
            :ok

          not eligible?(alert) or revision(alert) != run.revision ->
            update!(current, state: "cancelled")

          ids == [] ->
            finish_run(alert, current)

          true ->
            seed_states(alert, ids, legacy)
            states = alert |> states(ids) |> lock("FOR UPDATE") |> Repo.all() |> Map.new(&{&1.test_case_id, &1})
            Enum.each(proposals, fn proposal -> reserve(alert, Map.fetch!(states, proposal.test_case_id), proposal) end)
            current |> update!(cursor: cursor) |> enqueue_page()
        end
      end)

    :ok
  end

  defp seed_states(alert, ids, legacy) do
    legacy = Map.new(legacy, &{&1.test_case_id, &1})
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(ids, fn id ->
        event = Map.get(legacy, id)

        %{
          id: UUIDv7.generate(),
          alert_id: alert.id,
          generation: Alert.event_generation(alert),
          test_case_id: id,
          status: if(event, do: "triggered", else: "recovered"),
          triggered_at: if(event, do: DateTime.from_naive!(event.triggered_at, "Etc/UTC")),
          sequence: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(TestState, rows, on_conflict: :nothing, conflict_target: [:alert_id, :generation, :test_case_id])
  end

  def reserve(alert, state, proposal) do
    force = Map.get(proposal, :force, false)

    if force or (is_nil(state.pending_transition_id) and state.status != proposal.status) do
      transition =
        Repo.insert!(%Transition{
          state_id: state.id,
          revision: revision(alert),
          sequence: state.sequence + 1,
          status: proposal.status,
          actions: proposal.actions,
          depth: Map.get(proposal, :depth, 0),
          source_id: Map.get(proposal, :source_id)
        })

      update!(state, sequence: transition.sequence, pending_transition_id: state.pending_transition_id || transition.id)
      Oban.insert!(TransitionWorker.new(%{transition_id: transition.id}))
      transition
    end
  end

  # Called inside the fan-out transaction. Source identity deduplicates replay,
  # while sequence and pending_transition_id order multiple independent events.
  def enqueue_event(alert, test_case_id, source_id, depth) do
    current = locked_alert(alert.id)

    if current.enabled and revision(current) == revision(alert) do
      seed_states(current, [test_case_id], [])
      state = current |> states([test_case_id]) |> lock("FOR UPDATE") |> Repo.one!()

      if !Repo.exists?(from(t in Transition, where: t.state_id == ^state.id and t.source_id == ^source_id)) do
        transition =
          Repo.insert!(%Transition{
            state_id: state.id,
            revision: revision(current),
            sequence: state.sequence + 1,
            status: "triggered",
            actions: current.trigger_actions,
            source_id: source_id,
            depth: depth
          })

        update!(state, sequence: transition.sequence, pending_transition_id: state.pending_transition_id || transition.id)
        Oban.insert!(TransitionWorker.new(%{transition_id: transition.id}))
      end
    end
  end

  defp finish_run(alert, run) do
    update!(run, state: "completed")

    cond do
      run.baseline ->
        update!(alert,
          baseline_established_at: DateTime.truncate(run.evaluated_at, :second),
          last_scoped_evaluation_inserted_at: DateTime.truncate(run.evaluated_at, :second),
          trigger_config: Map.delete(alert.trigger_config, "apply_actions_to_existing_matches")
        )

      run.scope["end"] ->
        {:ok, at, _} = DateTime.from_iso8601(run.scope["end"])
        {:ok, alert} = Automations.update_alert_scoped_evaluation_cursor(alert, DateTime.truncate(at, :second))
        if run.scope["more"], do: schedule_locked(alert, %{"evaluate_recent_test_case_runs" => true})

      true ->
        :ok
    end
  end

  defp states(alert, ids) do
    generation = Alert.event_generation(alert)
    from(s in TestState, where: s.alert_id == ^alert.id and s.generation == ^generation and s.test_case_id in ^ids)
  end

  defp enqueue_page(run), do: Oban.insert!(EvaluationPageWorker.new(%{evaluation_id: run.id}))

  defp eligible?(alert),
    do:
      alert.enabled and alert.durable_execution and Alert.recovery_ledger?(alert) and
        Alert.trigger_window_supported?(alert)

  def locked_alert(id), do: Repo.one!(from(a in Alert, where: a.id == ^id, lock: "FOR UPDATE"))
  def update!(record, attrs), do: record |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp naive(value) do
    {:ok, at, _} = DateTime.from_iso8601(value)
    DateTime.to_naive(at)
  end

  def with_lock(key, fun) do
    if Environment.database_pooled?() do
      raise "durable automation workers require a direct PostgreSQL connection for session locks"
    end

    # Never put a session lock on a reusable Repo connection: a killed borrower
    # can return it to the pool without running its `after` block. This linked,
    # single-session connection closes with its owner. Reconnect is disabled so
    # losing the lock session cannot silently leave an unfenced worker running.
    opts =
      Repo.config()
      |> Keyword.drop([:name, :pool, :pool_size, :url])
      |> Keyword.merge(pool_size: 1, backoff_type: :stop, max_restarts: 0, connect_timeout: 5000, timeout: 5000)

    {:ok, connection} = Postgrex.start_link(opts)

    try do
      case Postgrex.query!(connection, "SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [key]) do
        %{rows: [[true]]} -> fun.()
        _ -> {:snooze, 1}
      end
    after
      if Process.alive?(connection), do: GenServer.stop(connection, :normal)
    end
  end
end
