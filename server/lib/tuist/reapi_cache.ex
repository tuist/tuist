defmodule Tuist.ReapiCache do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache.CacheEvent

  def create_cache_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    observed_now = DateTime.utc_now()

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
          observed_at: Map.get(event, :observed_at, observed_now),
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(CacheEvent, entries)
  end

  def summary(project_id, {start_datetime, end_datetime}) do
    end_datetime = DateTime.add(end_datetime, 1, :second)

    summary =
      ClickHouseRepo.one(
        from(e in CacheEvent,
          where: e.project_id == ^project_id and e.observed_at >= ^start_datetime and e.observed_at < ^end_datetime,
          select: %{
            hits: coalesce(sum(fragment("if(? = 'action_cache' AND ? = 'hit', 1, 0)", e.operation, e.outcome)), 0),
            misses: coalesce(sum(fragment("if(? = 'action_cache' AND ? = 'miss', 1, 0)", e.operation, e.outcome)), 0),
            download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", e.outcome, e.size)), 0),
            upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", e.outcome, e.size)), 0),
            last_observed_at: fragment("maxOrNull(?)", e.observed_at)
          }
        )
      )

    lookups = summary.hits + summary.misses

    Map.put(summary, :hit_rate, if(lookups == 0, do: nil, else: Float.round(summary.hits / lookups * 100, 1)))
  end
end
