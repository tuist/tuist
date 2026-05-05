defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

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
      trigger_config: %{"threshold" => 3, "window" => "30d"},
      cadence: "5m",
      trigger_actions: [%{"type" => "add_label", "label" => "flaky"}],
      recovery_enabled: true,
      recovery_config: %{"window" => "14d"},
      recovery_actions: [%{"type" => "remove_label", "label" => "flaky"}]
    }
  end

  def update_alert(%Alert{} = alert, attrs) do
    alert
    |> Alert.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert(%Alert{} = alert) do
    Repo.delete(alert)
  end

  @doc """
  Returns currently active alert events for an alert (latest status = "triggered").
  Uses argMax to find the most recent status per test_case_id from the append-only log.
  """
  def list_active_alert_events(alert_id) do
    ClickHouseRepo.all(
      from(e in AlertEvent,
        where: e.alert_id == ^alert_id,
        group_by: e.test_case_id,
        having: fragment("argMax(?, ?) = 'triggered'", e.status, e.inserted_at),
        select: %{
          test_case_id: e.test_case_id,
          triggered_at: fragment("argMax(?, ?)", e.triggered_at, e.inserted_at)
        }
      )
    )
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

  Looks up enabled `manually_marked_flaky` alerts for the test case's project
  and runs their trigger or recovery actions immediately. This is the
  event-driven counterpart to the scheduled `AlertEvaluationWorker` and is
  invoked from `Tuist.Tests.update_test_case/3` when a user manually flips
  `is_flaky`.

  Recognised events: `:marked_flaky`, `:unmarked_flaky`. Other events are
  ignored so this can be safely called for every test case event the caller
  produces.
  """
  def dispatch_test_case_event(:marked_flaky, %{id: test_case_id, project_id: project_id}) do
    project_id
    |> manually_marked_flaky_alerts(recovery: false)
    |> Enum.each(fn alert ->
      run_event_actions(alert, test_case_id, alert.trigger_actions, "triggered")
    end)

    :ok
  end

  def dispatch_test_case_event(:unmarked_flaky, %{id: test_case_id, project_id: project_id}) do
    project_id
    |> manually_marked_flaky_alerts(recovery: true)
    |> Enum.each(fn alert ->
      run_event_actions(alert, test_case_id, alert.recovery_actions, "recovered")
    end)

    :ok
  end

  def dispatch_test_case_event(_event, _test_case), do: :ok

  defp manually_marked_flaky_alerts(project_id, opts) do
    base =
      from(a in Alert,
        where: a.project_id == ^project_id,
        where: a.monitor_type == "manually_marked_flaky",
        where: a.enabled == true
      )

    base =
      if Keyword.get(opts, :recovery, false) do
        from(a in base, where: a.recovery_enabled == true)
      else
        base
      end

    Repo.all(base)
  end

  defp run_event_actions(alert, test_case_id, actions, status) do
    entity = %{type: :test_case, id: test_case_id}

    case ActionExecutor.execute_actions(actions, alert, entity) do
      :ok ->
        now = NaiveDateTime.utc_now()

        attrs = %{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: status,
          triggered_at: now
        }

        attrs =
          if status == "recovered" do
            Map.put(attrs, :recovered_at, now)
          else
            attrs
          end

        create_alert_event(attrs)

      {:error, reason} ->
        Logger.error("Alert #{alert.id} #{status} actions failed for test_case #{test_case_id}: #{inspect(reason)}")
    end
  end
end
