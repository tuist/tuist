defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.Automations.Alerts.PendingTestCaseEvaluation
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  # Backstop for automation chains that accidentally form a cycle (e.g. an
  # alert subscribed to `state_changed_to_muted` whose action mutes the test
  # case). Tracked per-process so each `update_test_case/3` entry-point gets
  # its own counter and concurrent updates don't interfere.
  @max_dispatch_depth 10
  @dispatch_depth_key :tuist_automation_dispatch_depth
  @flaky_monitor_types ~w(flakiness_rate flaky_run_count)

  def list_alerts(project_id) do
    Alert
    |> where(project_id: ^project_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_alert(id) do
    case Repo.get(Alert, id) do
      nil -> {:error, :not_found}
      alert -> {:ok, alert}
    end
  end

  def create_alert(attrs) do
    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
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

  def update_alert(%Alert{} = alert, attrs) do
    attrs = maybe_reset_baseline(alert, attrs)

    alert
    |> Alert.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_reset_baseline(alert, attrs) do
    if monitor_definition_changed?(alert, attrs) do
      reset_baseline(attrs)
    else
      attrs
    end
  end

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
  Uses argMax to find the most recent status per test_case_id from the append-only log.
  """
  def list_active_alert_events(alert_id, test_case_ids \\ nil) do
    AlertEvent
    |> where(alert_id: ^alert_id)
    |> filter_alert_events_by_test_case_ids(test_case_ids)
    |> group_by([e], e.test_case_id)
    |> having([e], fragment("argMax(?, ?) = 'triggered'", e.status, e.inserted_at))
    |> select([e], %{
      test_case_id: e.test_case_id,
      triggered_at: fragment("argMax(?, ?)", e.triggered_at, e.inserted_at)
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

      Enum.each(alerts, fn alert ->
        insert_pending_alert_test_case_ids(alert.id, test_case_ids)
        enqueue_pending_alert_evaluation(alert)
      end)

      :ok
    end
  end

  def enqueue_pending_alert_evaluation(%Alert{} = alert, opts \\ []) do
    schedule_in = Keyword.get(opts, :schedule_in, alert_evaluation_schedule_in())

    {:ok, _job} =
      %{alert_id: alert.id, drain_pending_test_case_ids: true}
      |> AlertEvaluationWorker.new(
        schedule_in: schedule_in,
        unique: [
          keys: [:alert_id, :drain_pending_test_case_ids],
          period: :infinity,
          states: [:available, :scheduled]
        ]
      )
      |> Oban.insert()

    :ok
  end

  def with_pending_alert_test_case_ids(alert_id, fun) do
    pending_evaluations =
      Repo.all(
        from(p in PendingTestCaseEvaluation,
          where: p.alert_id == ^alert_id,
          order_by: [asc: p.inserted_at, asc: p.test_case_id],
          select: %{test_case_id: p.test_case_id, generation: p.generation}
        )
      )

    test_case_ids = Enum.map(pending_evaluations, & &1.test_case_id)

    if test_case_ids == [] do
      :ok
    else
      result = fun.(test_case_ids)
      delete_pending_alert_test_case_evaluations(alert_id, pending_evaluations)
      result
    end
  end

  def list_pending_alert_test_case_ids(alert_id) do
    Repo.all(
      from(p in PendingTestCaseEvaluation,
        where: p.alert_id == ^alert_id,
        order_by: [asc: p.inserted_at, asc: p.test_case_id],
        select: p.test_case_id
      )
    )
  end

  def pending_alert_test_case_ids?(alert_id) do
    Repo.exists?(from(p in PendingTestCaseEvaluation, where: p.alert_id == ^alert_id))
  end

  def delete_pending_alert_test_case_ids(alert_id) do
    Repo.delete_all(from(p in PendingTestCaseEvaluation, where: p.alert_id == ^alert_id))
    :ok
  end

  defp insert_pending_alert_test_case_ids(alert_id, test_case_ids) do
    now = DateTime.utc_now(:second)

    entries =
      Enum.map(test_case_ids, fn test_case_id ->
        %{alert_id: alert_id, test_case_id: test_case_id, generation: 1, inserted_at: now}
      end)

    Repo.insert_all(PendingTestCaseEvaluation, entries,
      on_conflict: [set: [inserted_at: now], inc: [generation: 1]],
      conflict_target: [:alert_id, :test_case_id]
    )
  end

  defp delete_pending_alert_test_case_evaluations(_alert_id, []), do: :ok

  defp delete_pending_alert_test_case_evaluations(alert_id, pending_evaluations) do
    test_case_ids = Enum.map(pending_evaluations, &Ecto.UUID.dump!(&1.test_case_id))
    generations = Enum.map(pending_evaluations, & &1.generation)

    Repo.query!(
      """
      DELETE FROM automation_alert_pending_test_case_evaluations AS pending
      USING unnest($2::uuid[], $3::bigint[]) AS evaluated(test_case_id, generation)
      WHERE pending.alert_id = $1::uuid
        AND pending.test_case_id = evaluated.test_case_id
        AND pending.generation = evaluated.generation
      """,
      [Ecto.UUID.dump!(alert_id), test_case_ids, generations]
    )

    :ok
  end

  defp alert_evaluation_schedule_in do
    div(Environment.clickhouse_flush_interval_ms(), 1000) + 1
  end

  @doc """
  Appends an alert event to the log.
  """
  def create_alert_event(attrs) do
    now = NaiveDateTime.utc_now()

    record =
      attrs
      |> Map.put_new(:id, UUIDv7.generate())
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

  defp subscribed_alerts(%{project_id: project_id}, subscription_key) do
    project_id
    |> test_updated_alerts()
    |> Enum.filter(&subscribed?(&1, subscription_key))
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
          test_case_id: test_case_id,
          status: "triggered",
          triggered_at: NaiveDateTime.utc_now()
        })

      {:error, reason} ->
        Logger.error("Alert #{alert.id} actions failed for test_case #{test_case_id}: #{inspect(reason)}")
    end
  end
end
