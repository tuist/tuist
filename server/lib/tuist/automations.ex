defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Ecto.Multi
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.BaselineAttempt
  alias Tuist.Automations.Alerts.BaselineResult
  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.Automations.Alerts.Revision
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun

  require Logger

  # Backstop for automation chains that accidentally form a cycle (e.g. an
  # alert subscribed to `state_changed_to_muted` whose action mutes the test
  # case). Tracked per-process so each `update_test_case/3` entry-point gets
  # its own counter and concurrent updates don't interfere.
  @max_dispatch_depth 10
  @dispatch_depth_key :tuist_automation_dispatch_depth
  @flaky_monitor_types ~w(flakiness_rate flaky_run_count reliability_rate)
  # Changed test cases are returned in the rolling aggregate table's primary-key
  # order. Splitting that ordered list into several bounded ranges lets
  # ClickHouse prune the granules between ranges instead of treating a sparse
  # project-wide identifier set as one scan.
  @max_scoped_evaluation_range_size 2000
  @minimum_scoped_evaluation_ranges 4
  @revision_fields ~w(
    name
    enabled
    monitor_type
    trigger_config
    cadence
    trigger_actions
    recovery_enabled
    recovery_config
    recovery_actions
  )a
  @max_scoped_evaluation_window_seconds [minute: 15] |> to_timeout() |> div(1000)
  @baseline_evaluation_batch_size 2000
  @baseline_event_batch_size 500
  @baseline_enumeration_settings [
    max_threads: 1,
    max_memory_usage: 128 * 1024 * 1024,
    optimize_aggregation_in_order: 1
  ]

  def list_alerts(project_id) do
    Alert
    |> where(project_id: ^project_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> Repo.all()
  end

  def get_alert(id) do
    case Repo.get(Alert, id) do
      nil -> {:error, :not_found}
      alert -> {:ok, alert}
    end
  end

  def list_alert_revisions(alert_id, opts \\ []) do
    Revision
    |> where(automation_alert_id: ^alert_id)
    |> before_alert_revision(Keyword.get(opts, :before))
    |> order_by(desc: :recorded_at, desc: :id)
    |> limit_alert_revisions(Keyword.get(opts, :limit))
    |> preload(actor: :account)
    |> Repo.all()
  end

  def get_alert_revision(alert_id, revision_id) do
    case Repo.get_by(Revision, id: revision_id, automation_alert_id: alert_id) do
      nil -> {:error, :not_found}
      revision -> {:ok, revision}
    end
  end

  def redact_revision(%Revision{} = revision) do
    %{
      id: revision.id,
      event: revision.event,
      source: revision.source,
      actor: revision_actor(revision),
      changes: redact_revision_changes(revision.changes),
      snapshot: redact_revision_snapshot(revision.snapshot),
      inserted_at: revision.inserted_at
    }
  end

  defp revision_actor(%{actor: nil}), do: nil

  defp revision_actor(%{actor: actor}) do
    %{id: actor.id, name: actor.account.name, email: actor.email}
  end

  defp redact_revision_changes(changes) when is_map(changes) do
    redact_revision_actions(changes, fn action_change ->
      action_change
      |> Map.update("from", [], &redact_actions/1)
      |> Map.update("to", [], &redact_actions/1)
    end)
  end

  defp redact_revision_changes(_changes), do: %{}

  defp redact_revision_snapshot(snapshot) when is_map(snapshot) do
    redact_revision_actions(snapshot, &redact_actions/1)
  end

  defp redact_revision_snapshot(_snapshot), do: %{}

  defp redact_revision_actions(content, redactor) do
    Enum.reduce(["trigger_actions", "recovery_actions"], content, fn field, acc ->
      Map.update(acc, field, [], redactor)
    end)
  end

  defp redact_actions(actions) when is_list(actions), do: Enum.map(actions, &redact_action/1)
  defp redact_actions(_actions), do: []

  defp before_alert_revision(query, nil), do: query

  defp before_alert_revision(query, %Revision{recorded_at: recorded_at, id: id}) do
    where(
      query,
      [revision],
      revision.recorded_at < ^recorded_at or
        (revision.recorded_at == ^recorded_at and revision.id < ^id)
    )
  end

  defp limit_alert_revisions(query, limit) when is_integer(limit) and limit > 0 do
    limit(query, ^limit)
  end

  defp limit_alert_revisions(query, _limit), do: query

  def create_alert(attrs, opts \\ []) do
    Multi.new()
    |> Multi.insert(:alert, Alert.changeset(%Alert{}, attrs))
    |> Multi.run(:revision, fn repo, %{alert: alert} ->
      insert_alert_revision(repo, nil, alert, "created", opts)
    end)
    |> Repo.transaction()
    |> unwrap_create_alert_transaction()
  end

  @doc """
  Returns the default alert attrs seeded on every new project so flaky
  detection works out of the box. Kept as a single source of truth so the
  `Projects.create_project` path and the backfill migration stay in sync.
  """
  def default_alert_attrs(project_id) do
    %{
      project_id: project_id,
      name: "Flaky test detection",
      enabled: true,
      monitor_type: "flaky_run_count",
      trigger_config: %{"threshold" => 3, "window_type" => "last_days", "window" => "30d"},
      cadence: "5m",
      trigger_actions: [%{"type" => "add_label", "label" => "flaky"}],
      recovery_enabled: true,
      recovery_config: %{"window_type" => "last_days", "window" => "14d"},
      recovery_actions: [%{"type" => "remove_label", "label" => "flaky"}]
    }
  end

  def update_alert(%Alert{id: alert_id}, attrs, opts \\ []) do
    fn ->
      alert =
        Repo.one!(
          from(current in Alert,
            where: current.id == ^alert_id,
            lock: "FOR UPDATE"
          )
        )

      monitor_definition_changed? = monitor_definition_changed?(alert, attrs)
      attrs = maybe_reset_baseline(attrs, monitor_definition_changed?)
      changeset = Alert.changeset(alert, attrs)

      changeset =
        if monitor_definition_changed? do
          Ecto.Changeset.put_change(changeset, :baseline_generation, alert.baseline_generation + 1)
        else
          changeset
        end

      updated_alert =
        case Repo.update(changeset) do
          {:ok, updated_alert} -> updated_alert
          {:error, reason} -> Repo.rollback({:alert, reason})
        end

      case insert_alert_revision(Repo, alert, updated_alert, "updated", opts) do
        {:ok, _revision} -> updated_alert
        {:error, reason} -> Repo.rollback({:revision, reason})
      end
    end
    |> Repo.transaction()
    |> unwrap_update_alert_transaction()
  end

  defp unwrap_create_alert_transaction({:ok, %{alert: alert}}), do: {:ok, alert}
  defp unwrap_create_alert_transaction({:error, :alert, reason, _changes}), do: {:error, reason}
  defp unwrap_create_alert_transaction({:error, :revision, _reason, _changes}), do: {:error, :revision}

  defp unwrap_update_alert_transaction({:ok, alert}), do: {:ok, alert}
  defp unwrap_update_alert_transaction({:error, {:alert, reason}}), do: {:error, reason}
  defp unwrap_update_alert_transaction({:error, {:revision, _reason}}), do: {:error, :revision}

  defp insert_alert_revision(repo, previous_alert, alert, event, opts) do
    changes = alert_revision_changes(previous_alert, alert)

    if event == "updated" and changes == %{} do
      {:ok, nil}
    else
      attrs = %{
        automation_alert_id: alert.id,
        actor_id: alert_revision_actor_id(opts),
        event: event,
        source: Keyword.get(opts, :source, "system"),
        changes: changes,
        snapshot: alert_revision_snapshot(alert)
      }

      %Revision{}
      |> Revision.changeset(attrs)
      |> repo.insert()
    end
  end

  defp alert_revision_actor_id(opts) do
    case Keyword.get(opts, :actor) do
      %{id: id} -> id
      _ -> Keyword.get(opts, :actor_id)
    end
  end

  defp alert_revision_changes(nil, _alert), do: %{}

  defp alert_revision_changes(previous_alert, alert) do
    Enum.reduce(@revision_fields, %{}, fn field, changes ->
      previous_value = revision_value(field, Map.fetch!(previous_alert, field))
      current_value = revision_value(field, Map.fetch!(alert, field))

      if previous_value == current_value do
        changes
      else
        Map.put(changes, Atom.to_string(field), %{"from" => previous_value, "to" => current_value})
      end
    end)
  end

  defp alert_revision_snapshot(alert) do
    Map.new(@revision_fields, fn field ->
      {Atom.to_string(field), revision_value(field, Map.fetch!(alert, field))}
    end)
  end

  defp revision_value(field, actions) when field in [:trigger_actions, :recovery_actions] do
    Enum.map(actions, &redact_webhook_url/1)
  end

  defp revision_value(_field, value), do: value

  def redact_action(action) when is_map(action), do: Map.delete(action, "webhook_url_encrypted")

  defp redact_webhook_url(action) do
    case Map.pop(action, "webhook_url_encrypted") do
      {webhook_url, action} when is_binary(webhook_url) ->
        Map.put(action, "webhook_url_digest", :sha256 |> :crypto.hash(webhook_url) |> Base.encode16(case: :lower))

      {_webhook_url, action} ->
        action
    end
  end

  defp maybe_reset_baseline(attrs, true), do: reset_baseline(attrs)
  defp maybe_reset_baseline(attrs, false), do: attrs

  defp reset_baseline(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "baseline_established_at", nil)
    else
      Map.put(attrs, :baseline_established_at, nil)
    end
  end

  defp monitor_definition_changed?(alert, attrs) do
    changed_attr?(alert, attrs, :monitor_type) or changed_attr?(alert, attrs, :trigger_config)
  end

  defp changed_attr?(alert, attrs, key) do
    case fetch_attr(attrs, key) do
      {:ok, value} -> Map.fetch!(alert, key) != value
      :error -> false
    end
  end

  defp fetch_attr(attrs, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> {:ok, Map.fetch!(attrs, key)}
      Map.has_key?(attrs, string_key) -> {:ok, Map.fetch!(attrs, string_key)}
      true -> :error
    end
  end

  def delete_alert(%Alert{} = alert) do
    Repo.delete(alert)
  end

  @doc """
  Returns currently active alert events for an alert (latest status = "triggered").

  A publication retry can append a byte-identical deterministic baseline event.
  Resolving the latest status per test case already makes those retries
  invisible, without a separate hash aggregation over event identifiers.
  """
  def list_active_alert_events(alert_or_id, test_case_ids \\ nil)

  # Callers holding the alert already carry the generation the events are
  # scoped to, so taking it off the struct skips a lookup that the evaluation
  # worker would otherwise repeat for every range it evaluates.
  def list_active_alert_events(%Alert{id: alert_id, baseline_generation: baseline_generation}, test_case_ids) do
    active_alert_events(alert_id, baseline_generation, test_case_ids)
  end

  def list_active_alert_events(alert_id, test_case_ids) do
    baseline_generation =
      Repo.one(from(alert in Alert, where: alert.id == ^alert_id, select: alert.baseline_generation))

    active_alert_events(alert_id, baseline_generation, test_case_ids)
  end

  defp active_alert_events(alert_id, baseline_generation, test_case_ids) do
    AlertEvent
    |> where(alert_id: ^alert_id, baseline_generation: ^baseline_generation)
    |> filter_alert_events_by_test_case_ids(test_case_ids)
    |> group_by([event], event.test_case_id)
    |> having([event], fragment("argMax(?, ?) = 'triggered'", event.status, event.inserted_at))
    |> select([event], %{
      test_case_id: event.test_case_id,
      triggered_at: fragment("argMax(?, ?)", event.triggered_at, event.inserted_at)
    })
    |> ClickHouseRepo.all()
  end

  defp filter_alert_events_by_test_case_ids(query, nil), do: query
  defp filter_alert_events_by_test_case_ids(query, []), do: where(query, false)

  defp filter_alert_events_by_test_case_ids(query, test_case_ids) do
    where(query, [e], e.test_case_id in ^test_case_ids)
  end

  def enqueue_flaky_alert_evaluations(_project_id, []), do: :ok

  def enqueue_flaky_alert_evaluations(project_id, test_case_ids) do
    test_case_ids =
      test_case_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if test_case_ids == [] do
      :ok
    else
      alerts =
        Repo.all(
          from(a in Alert,
            where: a.project_id == ^project_id,
            where: a.enabled == true,
            where: a.monitor_type in ^@flaky_monitor_types
          )
        )

      alerts
      |> Enum.filter(&Alert.scoped_evaluation?/1)
      |> Enum.group_by(&Alert.cadence_seconds(&1.cadence))
      |> Enum.each(fn {_cadence_seconds, [alert | _alerts]} ->
        enqueue_scoped_alert_evaluation(alert)
      end)

      :ok
    end
  end

  def enqueue_scoped_alert_evaluation(%Alert{} = alert, opts \\ []) do
    schedule_in =
      Keyword.get(
        opts,
        :schedule_in,
        max(alert_evaluation_schedule_in(), Alert.cadence_seconds(alert.cadence))
      )

    {:ok, _job} =
      %{
        project_id: alert.project_id,
        cadence_seconds: Alert.cadence_seconds(alert.cadence),
        evaluate_recent_test_case_runs: true
      }
      |> AlertEvaluationWorker.new(
        schedule_in: schedule_in,
        unique: [
          keys: [:project_id, :cadence_seconds, :evaluate_recent_test_case_runs],
          period: :infinity,
          states: [:available, :scheduled, :executing, :retryable]
        ]
      )
      |> Oban.insert()

    :ok
  end

  def recent_test_case_run_changes_for_alert(%Alert{} = alert) do
    now = DateTime.utc_now(:second)
    cursor = scoped_evaluation_cursor(alert, now)
    recent_test_case_run_changes(alert.project_id, cursor, now)
  end

  def recent_test_case_run_changes_for_alerts([%Alert{} = alert | _alerts] = alerts) do
    now = DateTime.utc_now(:second)

    cursor =
      alerts
      |> Enum.map(&scoped_evaluation_cursor(&1, now))
      |> Enum.min(DateTime)

    recent_test_case_run_changes(alert.project_id, cursor, now)
  end

  defp recent_test_case_run_changes(project_id, cursor, now) do
    query_start = DateTime.add(cursor, -scoped_evaluation_cursor_lookback_seconds(), :second)

    window_end = Enum.min([DateTime.add(cursor, @max_scoped_evaluation_window_seconds, :second), now], DateTime)

    test_case_ids =
      ClickHouseRepo.all(
        from(r in {"test_case_runs_by_inserted_at", TestCaseRun},
          where: r.project_id == ^project_id,
          where: not is_nil(r.test_case_id),
          where: r.inserted_at >= ^DateTime.to_naive(query_start),
          where: r.inserted_at < ^DateTime.to_naive(window_end),
          group_by: r.test_case_id,
          order_by: [asc: r.test_case_id],
          select: r.test_case_id
        )
      )

    %{
      test_case_ids: test_case_ids,
      cursor: window_end,
      more?: DateTime.before?(window_end, now)
    }
  end

  def establish_alert_baseline(%Alert{} = alert, evaluate_batch) when is_function(evaluate_batch, 1) do
    case begin_alert_baseline(alert) do
      {:established, _alert} ->
        :ok

      {:ok, %BaselineAttempt{state: "evaluating"} = attempt} ->
        case evaluate_alert_baseline(attempt, alert.project_id, evaluate_batch) do
          {:ok, publishing_attempt} -> publish_and_commit_alert_baseline(publishing_attempt)
          {:error, :stale} -> :ok
        end

      {:ok, %BaselineAttempt{state: "publishing"} = attempt} ->
        publish_and_commit_alert_baseline(attempt)

      {:ok, %BaselineAttempt{state: "committed"}} ->
        :ok
    end
  end

  @doc false
  def begin_alert_baseline(%Alert{id: alert_id}) do
    {:ok, result} =
      Repo.transaction(fn ->
        alert =
          Repo.one!(
            from(current in Alert,
              where: current.id == ^alert_id,
              lock: "FOR UPDATE"
            )
          )

        if alert.baseline_established_at do
          {:established, alert}
        else
          attempt =
            Repo.get_by(BaselineAttempt,
              alert_id: alert.id,
              baseline_generation: alert.baseline_generation
            ) ||
              Repo.insert!(
                BaselineAttempt.changeset(%BaselineAttempt{}, %{
                  alert_id: alert.id,
                  baseline_generation: alert.baseline_generation,
                  cursor: DateTime.utc_now(:second)
                })
              )

          {:ok, attempt}
        end
      end)

    result
  end

  @doc false
  def list_alert_baseline_test_case_page(project_id, cursor) do
    query =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        group_by: [
          test_case.module_name,
          test_case.suite_name,
          test_case.name,
          test_case.id
        ],
        order_by: [
          asc: test_case.module_name,
          asc: test_case.suite_name,
          asc: test_case.name,
          asc: test_case.id
        ],
        limit: @baseline_evaluation_batch_size,
        select: %{
          id: test_case.id,
          module_name: test_case.module_name,
          suite_name: test_case.suite_name,
          name: test_case.name
        }
      )

    query
    |> apply_alert_baseline_evaluation_cursor(cursor)
    |> ClickHouseRepo.all(settings: @baseline_enumeration_settings)
  end

  defp apply_alert_baseline_evaluation_cursor(query, nil), do: query

  defp apply_alert_baseline_evaluation_cursor(query, %{
         "module_name" => module_name,
         "suite_name" => suite_name,
         "name" => name,
         "id" => id
       }) do
    where(
      query,
      [test_case],
      test_case.module_name > ^module_name or
        (test_case.module_name == ^module_name and
           (test_case.suite_name > ^suite_name or
              (test_case.suite_name == ^suite_name and
                 (test_case.name > ^name or
                    (test_case.name == ^name and test_case.id > ^id)))))
    )
  end

  defp evaluate_alert_baseline(attempt, project_id, evaluate_batch) do
    case list_alert_baseline_test_case_page(project_id, attempt.evaluation_cursor) do
      [] ->
        finish_alert_baseline_evaluation(attempt)

      test_cases ->
        test_case_ids = Enum.map(test_cases, & &1.id)
        triggered_test_case_ids = test_case_ids |> evaluate_batch.() |> Enum.uniq()
        evaluation_cursor = baseline_evaluation_cursor(List.last(test_cases))

        case persist_alert_baseline_batch(
               attempt,
               evaluation_cursor,
               triggered_test_case_ids
             ) do
          {:ok, %BaselineAttempt{state: "evaluating"} = next_attempt} ->
            evaluate_alert_baseline(next_attempt, project_id, evaluate_batch)

          {:ok, %BaselineAttempt{} = next_attempt} ->
            {:ok, next_attempt}

          {:error, :stale} = error ->
            error
        end
    end
  end

  defp baseline_evaluation_cursor(test_case) do
    %{
      "module_name" => test_case.module_name,
      "suite_name" => test_case.suite_name,
      "name" => test_case.name,
      "id" => test_case.id
    }
  end

  @doc false
  def persist_alert_baseline_batch(%BaselineAttempt{} = attempt, evaluation_cursor, triggered_test_case_ids) do
    with_locked_alert_baseline_attempt(attempt, fn alert, current_attempt ->
      cond do
        stale_alert_baseline_attempt?(alert, current_attempt) ->
          Repo.rollback(:stale)

        current_attempt.state != "evaluating" or
            current_attempt.evaluation_cursor != attempt.evaluation_cursor ->
          current_attempt

        true ->
          now = DateTime.utc_now(:second)

          rows =
            Enum.map(triggered_test_case_ids, fn test_case_id ->
              %{
                attempt_id: current_attempt.id,
                test_case_id: test_case_id,
                inserted_at: now
              }
            end)

          Repo.insert_all(BaselineResult, rows,
            on_conflict: :nothing,
            conflict_target: [:attempt_id, :test_case_id]
          )

          current_attempt
          |> BaselineAttempt.changeset(%{evaluation_cursor: evaluation_cursor})
          |> Repo.update!()
      end
    end)
  end

  defp finish_alert_baseline_evaluation(%BaselineAttempt{} = attempt) do
    with_locked_alert_baseline_attempt(attempt, fn alert, current_attempt ->
      cond do
        stale_alert_baseline_attempt?(alert, current_attempt) ->
          Repo.rollback(:stale)

        current_attempt.state != "evaluating" or
            current_attempt.evaluation_cursor != attempt.evaluation_cursor ->
          current_attempt

        true ->
          current_attempt
          |> BaselineAttempt.changeset(%{state: "publishing"})
          |> Repo.update!()
      end
    end)
  end

  defp with_locked_alert_baseline_attempt(attempt, fun) do
    case Repo.transaction(fn ->
           alert =
             Repo.one!(
               from(current in Alert,
                 where: current.id == ^attempt.alert_id,
                 lock: "FOR UPDATE"
               )
             )

           current_attempt =
             Repo.one!(
               from(current in BaselineAttempt,
                 where: current.id == ^attempt.id,
                 lock: "FOR UPDATE"
               )
             )

           fun.(alert, current_attempt)
         end) do
      {:ok, current_attempt} -> {:ok, current_attempt}
      {:error, :stale} -> {:error, :stale}
    end
  end

  defp stale_alert_baseline_attempt?(alert, attempt) do
    alert.baseline_established_at != nil or
      alert.baseline_generation != attempt.baseline_generation
  end

  defp publish_and_commit_alert_baseline(%BaselineAttempt{} = attempt) do
    test_case_ids =
      BaselineResult
      |> where(attempt_id: ^attempt.id)
      |> maybe_filter_published_baseline_results(attempt.last_published_test_case_id)
      |> order_by(asc: :test_case_id)
      |> limit(@baseline_event_batch_size)
      |> select([result], result.test_case_id)
      |> Repo.all()

    case test_case_ids do
      [] ->
        commit_alert_baseline(attempt)

      test_case_ids ->
        now =
          attempt.cursor
          |> DateTime.to_naive()
          |> Map.put(:microsecond, {0, 6})

        records =
          Enum.map(test_case_ids, fn test_case_id ->
            %{
              id: deterministic_baseline_event_id(attempt.id, test_case_id),
              alert_id: attempt.alert_id,
              baseline_generation: attempt.baseline_generation,
              test_case_id: test_case_id,
              status: "triggered",
              triggered_at: now,
              inserted_at: now
            }
          end)

        IngestRepo.insert_all(AlertEvent, records,
          settings: [
            insert_deduplication_token:
              baseline_event_deduplication_token(
                attempt.id,
                attempt.last_published_test_case_id
              )
          ]
        )

        case advance_alert_baseline_publication(attempt, List.last(test_case_ids)) do
          {:ok, next_attempt} -> publish_and_commit_alert_baseline(next_attempt)
          {:error, :stale} -> :ok
        end
    end
  end

  defp maybe_filter_published_baseline_results(query, nil), do: query

  defp maybe_filter_published_baseline_results(query, test_case_id) do
    where(query, [result], result.test_case_id > ^test_case_id)
  end

  defp baseline_event_deduplication_token(attempt_id, last_published_test_case_id) do
    "automation-alert-baseline:#{attempt_id}:#{last_published_test_case_id || "start"}"
  end

  defp advance_alert_baseline_publication(attempt, last_published_test_case_id) do
    with_locked_alert_baseline_attempt(attempt, fn alert, current_attempt ->
      cond do
        stale_alert_baseline_attempt?(alert, current_attempt) ->
          Repo.rollback(:stale)

        current_attempt.state != "publishing" or
            current_attempt.last_published_test_case_id !=
              attempt.last_published_test_case_id ->
          current_attempt

        true ->
          current_attempt
          |> BaselineAttempt.changeset(%{
            last_published_test_case_id: last_published_test_case_id
          })
          |> Repo.update!()
      end
    end)
  end

  @doc false
  def commit_alert_baseline(%BaselineAttempt{} = attempt) do
    case Repo.transaction(fn ->
           alert =
             Repo.one!(
               from(current in Alert,
                 where: current.id == ^attempt.alert_id,
                 lock: "FOR UPDATE"
               )
             )

           current_attempt =
             Repo.one!(
               from(current in BaselineAttempt,
                 where: current.id == ^attempt.id,
                 lock: "FOR UPDATE"
               )
             )

           cond do
             alert.baseline_established_at != nil ->
               :ok

             alert.baseline_generation != current_attempt.baseline_generation ->
               Repo.rollback(:stale)

             current_attempt.state != "publishing" ->
               Repo.rollback(:not_ready)

             true ->
               current_attempt
               |> BaselineAttempt.changeset(%{state: "committed"})
               |> Repo.update!()

               alert
               |> Ecto.Changeset.change(
                 baseline_established_at: current_attempt.cursor,
                 last_scoped_evaluation_inserted_at: current_attempt.cursor
               )
               |> Repo.update!()

               Repo.delete_all(
                 from(result in BaselineResult,
                   where: result.attempt_id == ^current_attempt.id
                 )
               )

               :ok
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, :stale} -> :ok
      {:error, :not_ready} -> {:error, :not_ready}
    end
  end

  defp deterministic_baseline_event_id(attempt_id, test_case_id) do
    <<a::32, b::16, c::16, d::16, e::48>> =
      :sha256
      |> :crypto.hash("#{attempt_id}:#{test_case_id}")
      |> binary_part(0, 16)

    Ecto.UUID.cast!(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>)
  end

  def update_alert_scoped_evaluation_cursor(%Alert{} = alert, cursor) do
    cursor = later_cursor(alert.last_scoped_evaluation_inserted_at, cursor)

    alert
    |> Ecto.Changeset.change(last_scoped_evaluation_inserted_at: cursor)
    |> Repo.update()
  end

  def advance_alert_scoped_evaluation_cursors(alerts, cursor) do
    alert_ids = Enum.map(alerts, & &1.id)
    now = DateTime.utc_now(:second)

    {updated_count, nil} =
      Alert
      |> where([alert], alert.id in ^alert_ids)
      |> update(
        [alert],
        set: [
          last_scoped_evaluation_inserted_at:
            fragment(
              "GREATEST(COALESCE(?, ?), ?)",
              alert.last_scoped_evaluation_inserted_at,
              ^cursor,
              ^cursor
            ),
          updated_at: ^now
        ]
      )
      |> Repo.update_all([])

    {:ok, updated_count}
  end

  def scoped_evaluation_ranges([]), do: []

  def scoped_evaluation_ranges(test_case_ids) do
    range_size =
      test_case_ids
      |> length()
      |> div(@minimum_scoped_evaluation_ranges)
      |> max(1)
      |> min(@max_scoped_evaluation_range_size)

    Enum.chunk_every(test_case_ids, range_size)
  end

  defp alert_evaluation_schedule_in do
    div(Environment.clickhouse_flush_interval_ms(), 1000) + 1
  end

  defp scoped_evaluation_cursor(%Alert{last_scoped_evaluation_inserted_at: nil}, now), do: now
  defp scoped_evaluation_cursor(%Alert{last_scoped_evaluation_inserted_at: cursor}, _now), do: cursor

  defp scoped_evaluation_cursor_lookback_seconds do
    max(alert_evaluation_schedule_in(), 10)
  end

  defp later_cursor(nil, cursor), do: cursor

  defp later_cursor(current_cursor, cursor) do
    Enum.max([current_cursor, cursor], DateTime)
  end

  @doc """
  Appends an alert event to the log.
  """
  def create_alert_event(attrs) do
    now = NaiveDateTime.utc_now()

    record =
      attrs
      |> Map.put_new(:id, UUIDv7.generate())
      |> Map.put_new(:baseline_generation, 0)
      |> Map.put_new(:inserted_at, now)

    IngestRepo.insert_all(AlertEvent, [record])
    :ok
  end

  @doc """
  Dispatches an event-driven test case automation trigger.

  Event-driven monitors (`monitor_type: "test_updated"`) fire the moment a
  user-initiated change happens to a test case, rather than waiting for the
  scheduled `AlertEvaluationWorker`. They have no recovery semantics — each
  event is a discrete one-shot.

  Stripe-style subscription: each alert's `trigger_config["events"]` is a
  list of subscribed event names. We translate the raw test-case event
  (`:muted`, `:unmuted`, ...) into the user-facing event key and then fan
  out to every alert whose `events` array contains that key.

  Event mapping:
    * `:marked_flaky`   → `"marked_flaky"`
    * `:unmarked_flaky` → `"unmarked_flaky"`
    * `:muted`          → `"state_changed_to_muted"`
    * `:skipped`        → `"state_changed_to_skipped"`
    * `:unmuted`        → `"state_changed_to_enabled"` (back to enabled from muted)
    * `:unskipped`      → `"state_changed_to_enabled"` (back to enabled from skipped)

  Other events are ignored so this can be safely called for every test case
  event the caller produces.

  Automation actions that mutate the test case re-enter this dispatcher, so
  a chain like `marked_flaky → mute → state_changed_to_muted → ...` works
  out of the box. A per-process depth counter (max `#{@max_dispatch_depth}`)
  prevents accidental cycles from looping forever.
  """
  def dispatch_test_case_event(event_type, test_case) do
    with key when not is_nil(key) <- event_to_subscription_key(event_type),
         depth when depth < @max_dispatch_depth <- Process.get(@dispatch_depth_key, 0) do
      Process.put(@dispatch_depth_key, depth + 1)

      try do
        test_case
        |> subscribed_alerts(key)
        |> Enum.each(fn alert -> run_event_actions(alert, test_case.id) end)

        :ok
      after
        restore_dispatch_depth(depth)
      end
    else
      nil ->
        :ok

      depth when is_integer(depth) ->
        Logger.warning(
          "Aborting automation dispatch: depth #{depth} reached for test case #{test_case.id} on event #{event_type}. Likely a cycle in automation actions."
        )

        :ok
    end
  end

  defp restore_dispatch_depth(0), do: Process.delete(@dispatch_depth_key)
  defp restore_dispatch_depth(depth), do: Process.put(@dispatch_depth_key, depth)

  defp event_to_subscription_key(:marked_flaky), do: "marked_flaky"
  defp event_to_subscription_key(:unmarked_flaky), do: "unmarked_flaky"
  defp event_to_subscription_key(:muted), do: "state_changed_to_muted"
  defp event_to_subscription_key(:skipped), do: "state_changed_to_skipped"
  defp event_to_subscription_key(:unmuted), do: "state_changed_to_enabled"
  defp event_to_subscription_key(:unskipped), do: "state_changed_to_enabled"
  defp event_to_subscription_key(_), do: nil

  defp subscribed_alerts(%{project_id: project_id, id: test_case_id}, subscription_key) do
    alerts =
      project_id
      |> test_updated_alerts()
      |> Enum.filter(&subscribed?(&1, subscription_key))

    filter_by_trigger_state(alerts, project_id, test_case_id)
  end

  defp filter_by_trigger_state([], _project_id, _test_case_id), do: []

  defp filter_by_trigger_state(alerts, project_id, test_case_id) do
    if Enum.any?(alerts, &has_trigger_state_filter?/1) do
      states = Tests.get_test_case_states(project_id, [test_case_id])
      current_state = Map.get(states, test_case_id, %{state: "enabled"}).state

      Enum.filter(alerts, fn alert ->
        case Map.get(alert.trigger_config || %{}, "states") do
          s when is_list(s) and s != [] -> current_state in s
          _ -> true
        end
      end)
    else
      alerts
    end
  end

  defp has_trigger_state_filter?(alert) do
    case Map.get(alert.trigger_config || %{}, "states") do
      s when is_list(s) and s != [] -> true
      _ -> false
    end
  end

  defp test_updated_alerts(project_id) do
    Repo.all(
      from(a in Alert,
        where: a.project_id == ^project_id,
        where: a.monitor_type == "test_updated",
        where: a.enabled == true
      )
    )
  end

  defp subscribed?(alert, subscription_key) do
    events = Map.get(alert.trigger_config || %{}, "events", [])
    is_list(events) and subscription_key in events
  end

  defp run_event_actions(alert, test_case_id) do
    entity = %{type: :test_case, id: test_case_id}

    case ActionExecutor.execute_actions(alert.trigger_actions, alert, entity) do
      :ok ->
        create_alert_event(%{
          alert_id: alert.id,
          baseline_generation: alert.baseline_generation,
          test_case_id: test_case_id,
          status: "triggered",
          triggered_at: NaiveDateTime.utc_now()
        })

      {:error, reason} ->
        Logger.error("Alert #{alert.id} actions failed for test_case #{test_case_id}: #{inspect(reason)}")
    end
  end
end
