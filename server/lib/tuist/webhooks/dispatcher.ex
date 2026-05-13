defmodule Tuist.Webhooks.Dispatcher do
  @moduledoc """
  Fans out domain events to every account-scoped webhook endpoint that has
  subscribed to the event type, by enqueuing a `Tuist.Webhooks.Workers.DeliveryWorker`
  job per match.

  Each call site builds the event payload (the `object` snapshot plus any
  additional context) and hands it off here; the dispatcher is responsible
  for adding the envelope metadata (`id`, `type`, `created`, `account`) and
  scheduling delivery. Failures while enqueuing a single endpoint are
  swallowed so one bad subscriber can't block delivery to the others.
  """
  alias Tuist.AppBuilds.Preview
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Webhooks
  alias Tuist.Webhooks.Workers.DeliveryWorker

  require Logger

  @doc """
  Dispatches a `test_case.updated` event for a single ClickHouse test_case
  row that has just changed (state, is_flaky, …).

  `event_types` is the list of canonical state-change names produced by
  `Tuist.Tests` for this write (`:marked_flaky`, `:muted`, `:unmuted`, …).
  They're forwarded in the payload so receivers can branch on the specific
  transition without diffing the snapshot themselves.
  """
  def dispatch_test_case_event(test_case, event_types, opts \\ []) do
    actor_id = Keyword.get(opts, :actor_id)
    alert_id = Keyword.get(opts, :alert_id)

    with %Projects.Project{account_id: account_id} <- Repo.get(Projects.Project, test_case.project_id),
         [_ | _] = endpoints <-
           Webhooks.list_endpoints_subscribed_to(account_id, "test_case.updated") do
      object = test_case_snapshot(test_case)

      Enum.each(endpoints, fn endpoint ->
        enqueue(endpoint, "test_case.updated", %{
          "object" => object,
          "events" => Enum.map(event_types, &Atom.to_string/1),
          "actor_id" => actor_id,
          "alert_id" => alert_id
        })
      end)

      :ok
    else
      _ -> :ok
    end
  end

  @doc """
  Dispatches a `test_case.created` event for each test case observed for
  the first time during an ingestion. The caller passes the project id
  (so we can resolve the account once for the batch) and the list of new
  test case maps; one Oban job is enqueued per (endpoint, test case)
  pair.
  """
  def dispatch_test_case_created(_project_id, []), do: :ok

  def dispatch_test_case_created(project_id, test_cases) when is_list(test_cases) do
    with %Projects.Project{account_id: account_id} <- Repo.get(Projects.Project, project_id),
         [_ | _] = endpoints <-
           Webhooks.list_endpoints_subscribed_to(account_id, "test_case.created") do
      Enum.each(test_cases, fn test_case ->
        object = test_case_snapshot(test_case)

        Enum.each(endpoints, fn endpoint ->
          enqueue(endpoint, "test_case.created", %{"object" => object})
        end)
      end)

      :ok
    else
      _ -> :ok
    end
  end

  @doc """
  Dispatches a `preview.uploaded` event when an app build has finished
  uploading to a preview. Receivers can drive workflows like "post to
  Slack when QA builds are ready" without polling.
  """
  def dispatch_preview_uploaded(%Preview{} = preview) do
    dispatch_preview_lifecycle_event(preview, "preview.uploaded")
  end

  @doc """
  Dispatches a `preview.deleted` event after a preview row is removed.
  """
  def dispatch_preview_deleted(%Preview{} = preview) do
    dispatch_preview_lifecycle_event(preview, "preview.deleted")
  end

  defp dispatch_preview_lifecycle_event(%Preview{} = preview, event_type) do
    preview = Repo.preload(preview, :project)

    with %Projects.Project{account_id: account_id} <- preview.project,
         [_ | _] = endpoints <-
           Webhooks.list_endpoints_subscribed_to(account_id, event_type) do
      object = preview_snapshot(preview)

      Enum.each(endpoints, fn endpoint ->
        enqueue(endpoint, event_type, %{"object" => object})
      end)

      :ok
    else
      _ -> :ok
    end
  end

  defp preview_snapshot(preview) do
    %{
      "id" => preview.id,
      "display_name" => preview.display_name,
      "bundle_identifier" => preview.bundle_identifier,
      "version" => preview.version,
      "project_id" => preview.project_id,
      "supported_platforms" => Enum.map(preview.supported_platforms || [], &to_string/1),
      "visibility" => to_string(preview.visibility),
      "git_branch" => preview.git_branch,
      "git_commit_sha" => preview.git_commit_sha,
      "git_ref" => preview.git_ref,
      "inserted_at" => format_datetime(preview.inserted_at)
    }
  end

  defp enqueue(endpoint, event_type, body) do
    event_id = Ecto.UUID.generate()

    payload =
      Map.merge(body, %{
        "id" => event_id,
        "type" => event_type,
        "created" => System.system_time(:second),
        "account" => %{"id" => endpoint.account_id},
        "endpoint" => %{"id" => endpoint.id, "name" => endpoint.name}
      })

    case %{
           "webhook_endpoint_id" => endpoint.id,
           "event_id" => event_id,
           "event_type" => event_type,
           "payload" => payload
         }
         |> DeliveryWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Webhook dispatch failed to enqueue for endpoint #{endpoint.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp test_case_snapshot(test_case) do
    %{
      "id" => test_case.id,
      "name" => test_case.name,
      "module_name" => test_case.module_name,
      "suite_name" => test_case.suite_name,
      "project_id" => test_case.project_id,
      "is_flaky" => test_case.is_flaky,
      "state" => test_case.state,
      "last_status" => test_case.last_status,
      "last_ran_at" => format_datetime(Map.get(test_case, :last_ran_at))
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_datetime(other), do: to_string(other)
end
