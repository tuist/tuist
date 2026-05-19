defmodule Tuist.Webhooks.Dispatcher do
  @moduledoc """
  Fans out domain events to every account-scoped webhook endpoint that has
  subscribed to the event type, by enqueuing a `Tuist.Webhooks.Workers.DeliveryWorker`
  job per match.

  Each call site builds the event payload (the `object` snapshot plus any
  additional context) and hands it off here; the dispatcher is responsible
  for adding the envelope metadata (`id`, `type`, `created`) and scheduling
  delivery. Fan-out goes through a single `Oban.insert_all/1` per dispatch
  call so one event with N subscribers is a single DB round-trip; the
  batch is wrapped in try/rescue so a DB-level failure logs and returns
  `:ok` instead of crashing the upstream write.
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

      body = %{
        "object" => object,
        "events" => Enum.map(event_types, &Atom.to_string/1),
        "actor_id" => actor_id,
        "alert_id" => alert_id
      }

      endpoints
      |> Enum.map(&build_job(&1, "test_case.updated", body))
      |> insert_jobs()
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
      test_cases
      |> Enum.flat_map(fn test_case ->
        body = %{"object" => test_case_snapshot(test_case)}
        Enum.map(endpoints, &build_job(&1, "test_case.created", body))
      end)
      |> insert_jobs()
    else
      _ -> :ok
    end
  end

  @doc """
  Dispatches a `preview.created` event when a new preview row has been
  inserted in the account. The caller gates this to the create branch of
  `AppBuilds.find_or_create_preview/1` so reused previews don't redeliver
  the event for an already-known resource.
  """
  def dispatch_preview_created(%Preview{} = preview) do
    dispatch_preview_lifecycle_event(preview, "preview.created")
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
      body = %{"object" => preview_snapshot(preview)}

      endpoints
      |> Enum.map(&build_job(&1, event_type, body))
      |> insert_jobs()
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
      "visibility" => maybe_to_string(preview.visibility),
      "git_branch" => preview.git_branch,
      "git_commit_sha" => preview.git_commit_sha,
      "git_ref" => preview.git_ref,
      "inserted_at" => format_datetime(preview.inserted_at)
    }
  end

  defp build_job(endpoint, event_type, body) do
    event_id = Ecto.UUID.generate()

    payload =
      Map.merge(body, %{
        "id" => event_id,
        "type" => event_type,
        "created" => System.system_time(:second)
      })

    DeliveryWorker.new(%{
      "webhook_endpoint_id" => endpoint.id,
      "event_id" => event_id,
      "event_type" => event_type,
      "payload" => payload
    })
  end

  # Single-batch insert so an event with N subscribers is one round-trip
  # to `oban_jobs` instead of N. A DB-level failure is logged and
  # swallowed — the upstream domain write shouldn't be torn down by a
  # webhook bookkeeping problem.
  defp insert_jobs([]), do: :ok

  defp insert_jobs(jobs) do
    _ = Oban.insert_all(jobs)
    :ok
  rescue
    error ->
      Logger.warning("Webhook dispatch failed to enqueue batch of #{length(jobs)} jobs: #{inspect(error)}")
      :ok
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

  # NaiveDateTime sources (CH `DateTime64(6, 'UTC')` columns Ecto
  # decodes as naive, PG `:utc_datetime` denormalized fields) are UTC
  # by convention here. Promote to `%DateTime{}` so the serialized
  # output carries the `Z` offset RFC 3339 requires — without it the
  # documented `date-time` schema rejects the value.
  defp format_datetime(%NaiveDateTime{} = dt), do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp format_datetime(other), do: to_string(other)

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)
end
