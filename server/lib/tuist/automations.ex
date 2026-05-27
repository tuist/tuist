defmodule Tuist.Automations do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.Automations.IssueLink
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  # Backstop for automation chains that accidentally form a cycle (e.g. an
  # alert subscribed to `state_changed_to_muted` whose action mutes the test
  # case). Tracked per-process so each `update_test_case/3` entry-point gets
  # its own counter and concurrent updates don't interfere.
  @max_dispatch_depth 10
  @dispatch_depth_key :tuist_automation_dispatch_depth

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
  Fetches the open `IssueLink` for an `(alert_id, test_case_id)` pair, if any.
  Used by the `create_github_issue` action to skip when an issue is already
  tracking this alert + test case.
  """
  def get_open_issue_link(alert_id, test_case_id) do
    Repo.one(
      from(l in IssueLink,
        where: l.alert_id == ^alert_id,
        where: l.test_case_id == ^test_case_id,
        where: l.state == "open"
      )
    )
  end

  @doc """
  Looks up an `IssueLink` from inbound webhook coordinates. Returns
  `{:ok, link}` or `{:error, :not_found}`.
  """
  def get_issue_link_by_github_coordinates(installation_id, repository_full_handle, issue_number) do
    query =
      from(l in IssueLink,
        where: l.github_repository_full_handle == ^repository_full_handle,
        where: l.github_issue_number == ^issue_number
      )

    query =
      if is_nil(installation_id) do
        where(query, [l], is_nil(l.github_app_installation_id))
      else
        where(query, [l], l.github_app_installation_id == ^installation_id)
      end

    case Repo.one(query) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  def create_issue_link(attrs) do
    attrs
    |> IssueLink.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Flips an `IssueLink` to the `:resolved` state, stamping `resolved_at`.
  No-op when the link is already resolved.
  """
  def resolve_issue_link(%IssueLink{state: "resolved"} = link), do: {:ok, link}

  def resolve_issue_link(%IssueLink{} = link) do
    link
    |> IssueLink.resolve_changeset(DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
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

  @doc """
  Dispatches a `github_issue` automation trigger for the closing of a
  Tuist-opened GitHub issue.

  Mirrors `dispatch_test_case_event/2`: looks up every `github_issue`
  alert in the project that has subscribed to `"closed"` in
  `trigger_config["events"]`, and runs its `trigger_actions` with
  `entity = %{type: :test_case, id: ...}` so the existing actions (e.g.
  `remove_label("flaky")`, `send_slack`) operate on the test case the
  issue tracked.

  Shares the per-process depth counter with `dispatch_test_case_event/2`
  so a chain like `issue_closed → remove_label(flaky) → unmarked_flaky → ...`
  can't loop forever across the two dispatchers.
  """
  def dispatch_issue_link_event(:closed, %{project_id: project_id} = _issue_link, test_case) do
    case Process.get(@dispatch_depth_key, 0) do
      depth when depth < @max_dispatch_depth ->
        Process.put(@dispatch_depth_key, depth + 1)

        try do
          project_id
          |> github_issue_alerts()
          |> Enum.filter(&subscribed?(&1, "closed"))
          |> Enum.each(fn alert -> run_event_actions(alert, test_case.id) end)

          :ok
        after
          restore_dispatch_depth(depth)
        end

      depth when is_integer(depth) ->
        Logger.warning(
          "Aborting automation dispatch: depth #{depth} reached for issue link on project #{project_id}. Likely a cycle in automation actions."
        )

        :ok
    end
  end

  defp github_issue_alerts(project_id) do
    Repo.all(
      from(a in Alert,
        where: a.project_id == ^project_id,
        where: a.monitor_type == "github_issue",
        where: a.enabled == true
      )
    )
  end

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
