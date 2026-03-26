defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  alias Tuist.Cache.CASEvent
  alias Tuist.IngestRepo

  @doc """
  Creates multiple CAS analytics events in a batch.

  ## Examples

      iex> create_cas_events([%{action: "upload", size: 1024, cas_id: "abc123", project_id: 1}, ...])
      {:ok, 2}
  """
  def create_cas_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          action: event.action,
          size: event.size,
          cas_id: event.cas_id,
          is_ci: Map.get(event, :is_ci, false),
          project_id: event.project_id,
          cache_endpoint: event.cache_endpoint,
          inserted_at: now
        }
      end)

    CASEvent.Buffer.insert_all(entries)
  end

  def last_24h_artifacts_count do
    yesterday = Date.to_string(Date.add(Date.utc_today(), -1))

    case IngestRepo.query(
           "SELECT sum(event_count) FROM cas_events_daily_stats WHERE date >= {since:Date}",
           %{"since" => yesterday}
         ) do
      {:ok, %{rows: [[count]]}} when not is_nil(count) -> count
      _ -> 0
    end
  end
end
