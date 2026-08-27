defmodule Tuist.ReapiCache do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache.CacheEvent

  def create_cache_events([]), do: {:ok, 0}

  def create_cache_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          client_kind: event.client_kind,
          operation: event.operation,
          outcome: event.outcome,
          action_digest: event.action_digest,
          size: event.size,
          duration_ms: event.duration_ms,
          invocation_id: event.invocation_id,
          action_mnemonic: event.action_mnemonic,
          target_label: event.target_label,
          configuration_id: event.configuration_id,
          project_id: event.project_id,
          account_handle: event.account_handle,
          project_handle: event.project_handle,
          cache_endpoint: event.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(CacheEvent, entries)
  end

  def summary(project_id) do
    result =
      ClickHouseRepo.one(
        from(e in CacheEvent,
          where: e.project_id == ^project_id and e.operation == "action_cache",
          select: %{
            hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", e.outcome)), 0),
            misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", e.outcome)), 0),
            download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", e.outcome, e.size)), 0),
            upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", e.outcome, e.size)), 0),
            last_observed_at: max(e.inserted_at)
          }
        )
      )

    summary = result || %{hits: 0, misses: 0, download_bytes: 0, upload_bytes: 0, last_observed_at: nil}
    lookups = summary.hits + summary.misses

    Map.put(summary, :hit_rate, if(lookups == 0, do: nil, else: Float.round(summary.hits / lookups * 100, 1)))
  end
end
