defmodule Tuist.Kura.Usage do
  @moduledoc """
  Persists Kura node usage rollups.
  """

  alias Tuist.Accounts
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Projects

  @max_events_per_batch 5_000

  def create_events(events) when is_list(events) and length(events) <= @max_events_per_batch do
    full_handles =
      events
      |> Enum.map(&"#{&1["tenant_id"]}/#{&1["namespace_id"]}")
      |> Enum.uniq()

    projects_by_handle = Projects.projects_by_full_handles(full_handles)

    account_ids_by_handle =
      events
      |> Enum.map(& &1["tenant_id"])
      |> Enum.uniq()
      |> Map.new(fn handle ->
        case Accounts.get_account_by_handle(handle) do
          nil -> {handle, nil}
          account -> {handle, account.id}
        end
      end)

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows =
      Enum.map(events, fn event ->
        tenant_id = event["tenant_id"]
        namespace_id = event["namespace_id"]
        full_handle = "#{tenant_id}/#{namespace_id}"
        project = Map.get(projects_by_handle, full_handle)

        %{
          event_id: event["event_id"],
          tenant_id: tenant_id,
          namespace_id: namespace_id,
          account_id: (project && project.account_id) || Map.get(account_ids_by_handle, tenant_id) || 0,
          project_id: (project && project.id) || 0,
          node_id: event["node_id"],
          region: event["region"],
          traffic_plane: event["traffic_plane"],
          direction: event["direction"],
          operation: event["operation"],
          protocol: event["protocol"],
          artifact_kind: event["artifact_kind"],
          bytes: event["bytes"],
          request_count: event["request_count"],
          window_start: unix_seconds_to_naive_datetime(event["window_start_unix_seconds"]),
          window_seconds: event["window_seconds"],
          inserted_at: now
        }
      end)

    if rows != [] do
      IngestRepo.insert_all(UsageEvent, rows)
    end

    {:ok, length(rows)}
  end

  def create_events(events) when is_list(events), do: {:error, :too_many_events}

  defp unix_seconds_to_naive_datetime(seconds) when is_integer(seconds) do
    seconds
    |> DateTime.from_unix!()
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end
end
