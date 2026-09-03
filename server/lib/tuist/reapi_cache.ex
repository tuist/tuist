defmodule Tuist.ReapiCache do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseFlop
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

  def list_cache_events(project_id, flop_params \\ %{}) do
    CacheEvent
    |> where([event], event.project_id == ^project_id)
    |> ClickHouseFlop.validate_and_run!(flop_params, for: CacheEvent)
  end

  def get_cache_event(project_id, cache_event_id) do
    cache_event =
      ClickHouseRepo.one(
        from(event in CacheEvent,
          where: event.project_id == ^project_id and event.id == ^cache_event_id,
          limit: 1
        )
      )

    case cache_event do
      nil -> {:error, :not_found}
      cache_event -> {:ok, cache_event}
    end
  end

  def invocation_summary(project_id, invocation_id) do
    project_id
    |> invocation_summaries([invocation_id])
    |> Map.get(invocation_id, empty_summary())
  end

  def invocation_summaries(_project_id, []), do: %{}

  def invocation_summaries(project_id, invocation_ids) do
    rows =
      ClickHouseRepo.all(
        from(event in CacheEvent,
          where: event.project_id == ^project_id and event.invocation_id in ^invocation_ids,
          group_by: event.invocation_id,
          select: %{
            invocation_id: event.invocation_id,
            hits:
              coalesce(
                sum(fragment("if(? = 'action_cache' AND ? = 'hit', 1, 0)", event.operation, event.outcome)),
                0
              ),
            misses:
              coalesce(
                sum(fragment("if(? = 'action_cache' AND ? = 'miss', 1, 0)", event.operation, event.outcome)),
                0
              ),
            download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", event.outcome, event.size)), 0),
            upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", event.outcome, event.size)), 0)
          }
        )
      )

    Map.new(rows, fn row ->
      lookups = row.hits + row.misses

      {row.invocation_id,
       row
       |> Map.delete(:invocation_id)
       |> Map.put(:hit_rate, if(lookups == 0, do: nil, else: Float.round(row.hits / lookups * 100, 1)))}
    end)
  end

  def empty_summary do
    %{hits: 0, misses: 0, download_bytes: 0, upload_bytes: 0, hit_rate: nil}
  end
end
