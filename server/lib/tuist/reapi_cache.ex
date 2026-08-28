defmodule Tuist.ReapiCache do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache.CacheEvent

  @invocation_timeline_event_limit 500

  def create_cache_events([]), do: {:ok, 0}

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

  def summary(project_id, opts \\ []) do
    query = cache_event_query(project_id, opts)

    result =
      ClickHouseRepo.one(
        from(e in query,
          select: %{
            hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", e.outcome)), 0),
            misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", e.outcome)), 0),
            download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", e.outcome, e.size)), 0),
            upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", e.outcome, e.size)), 0),
            read_duration_ms: coalesce(sum(fragment("if(? != 'write', ?, 0)", e.outcome, e.duration_ms)), 0),
            read_count: coalesce(sum(fragment("if(? != 'write', 1, 0)", e.outcome)), 0),
            write_duration_ms: coalesce(sum(fragment("if(? = 'write', ?, 0)", e.outcome, e.duration_ms)), 0),
            write_count: coalesce(sum(fragment("if(? = 'write', 1, 0)", e.outcome)), 0),
            download_throughput_bytes:
              coalesce(
                sum(
                  fragment(
                    "if(? = 'hit' AND ? > 0 AND ? > 0, ?, 0)",
                    e.outcome,
                    e.size,
                    e.duration_ms,
                    e.size
                  )
                ),
                0
              ),
            download_throughput_duration_ms:
              coalesce(
                sum(
                  fragment(
                    "if(? = 'hit' AND ? > 0 AND ? > 0, ?, 0)",
                    e.outcome,
                    e.size,
                    e.duration_ms,
                    e.duration_ms
                  )
                ),
                0
              ),
            upload_throughput_bytes:
              coalesce(
                sum(
                  fragment(
                    "if(? = 'write' AND ? > 0 AND ? > 0, ?, 0)",
                    e.outcome,
                    e.size,
                    e.duration_ms,
                    e.size
                  )
                ),
                0
              ),
            upload_throughput_duration_ms:
              coalesce(
                sum(
                  fragment(
                    "if(? = 'write' AND ? > 0 AND ? > 0, ?, 0)",
                    e.outcome,
                    e.size,
                    e.duration_ms,
                    e.duration_ms
                  )
                ),
                0
              ),
            last_observed_at: max(e.inserted_at)
          }
        )
      )

    summary = result || empty_summary_result()
    lookups = summary.hits + summary.misses

    summary
    |> Map.put(:hit_rate, if(lookups == 0, do: nil, else: Float.round(summary.hits / lookups * 100, 1)))
    |> Map.put(:transfer_bytes, summary.download_bytes + summary.upload_bytes)
    |> Map.put(:read_latency_ms, divide(summary.read_duration_ms, summary.read_count))
    |> Map.put(:write_latency_ms, divide(summary.write_duration_ms, summary.write_count))
    |> Map.put(
      :latency_ms,
      divide(summary.read_duration_ms + summary.write_duration_ms, summary.read_count + summary.write_count)
    )
    |> Map.put(
      :download_throughput_bytes_per_second,
      bytes_per_second(summary.download_throughput_bytes, summary.download_throughput_duration_ms)
    )
    |> Map.put(
      :upload_throughput_bytes_per_second,
      bytes_per_second(summary.upload_throughput_bytes, summary.upload_throughput_duration_ms)
    )
    |> Map.put(
      :throughput_bytes_per_second,
      bytes_per_second(
        summary.download_throughput_bytes + summary.upload_throughput_bytes,
        summary.download_throughput_duration_ms + summary.upload_throughput_duration_ms
      )
    )
  end

  def invocation_hit_rate_metrics(project_id, opts \\ []) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)

    query = """
    SELECT
      avgOrNull(hit_rate) AS average,
      quantileOrNull(0.99)(hit_rate) AS p99,
      quantileOrNull(0.9)(hit_rate) AS p90,
      quantileOrNull(0.5)(hit_rate) AS p50
    FROM (
      SELECT
        countIf(outcome = 'hit') * 100.0 /
          nullIf(countIf(outcome IN ('hit', 'miss')), 0) AS hit_rate
      FROM reapi_cache_events
      WHERE project_id = {project_id:Int64}
        AND operation = 'action_cache'
        AND invocation_id != ''
        AND inserted_at >= toDateTime({start_datetime:String}, 'UTC')
        AND inserted_at < toDateTime({end_datetime:String}, 'UTC')
      GROUP BY invocation_id
      HAVING countIf(outcome IN ('hit', 'miss')) > 0
    )
    """

    {:ok, %{rows: [[average, p99, p90, p50]]}} =
      ClickHouseRepo.query(query, %{
        project_id: project_id,
        start_datetime: datetime_string(start_datetime),
        end_datetime: datetime_string(end_datetime)
      })

    %{
      avg: percentage(average),
      p99: percentage(p99),
      p90: percentage(p90),
      p50: percentage(p50)
    }
  end

  def hit_rate_analytics(project_id, opts \\ []) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)

    hit_rates =
      from(event in cache_event_query(project_id, opts),
        group_by: fragment("toDate(?)", event.inserted_at),
        order_by: fragment("toDate(?)", event.inserted_at),
        select: %{
          date: fragment("toDate(?)", event.inserted_at),
          hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", event.outcome)), 0),
          misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", event.outcome)), 0)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn %{date: date, hits: hits, misses: misses} ->
        lookups = hits + misses
        {date, if(lookups == 0, do: 0, else: Float.round(hits / lookups * 100, 1))}
      end)

    dates = start_datetime |> DateTime.to_date() |> Date.range(DateTime.to_date(end_datetime)) |> Enum.to_list()

    %{
      dates: dates,
      values: Enum.map(dates, &Map.get(hit_rates, &1, 0)),
      hit_rate: summary(project_id, opts).hit_rate
    }
  end

  def analytics(project_id, opts \\ []) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)

    rows =
      from(event in cache_event_query(project_id, opts),
        group_by: fragment("toDate(?)", event.inserted_at),
        order_by: fragment("toDate(?)", event.inserted_at),
        select: %{
          date: fragment("toDate(?)", event.inserted_at),
          hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", event.outcome)), 0),
          misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", event.outcome)), 0),
          download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", event.outcome, event.size)), 0),
          upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", event.outcome, event.size)), 0),
          read_duration_ms: coalesce(sum(fragment("if(? != 'write', ?, 0)", event.outcome, event.duration_ms)), 0),
          read_count: coalesce(sum(fragment("if(? != 'write', 1, 0)", event.outcome)), 0),
          write_duration_ms: coalesce(sum(fragment("if(? = 'write', ?, 0)", event.outcome, event.duration_ms)), 0),
          write_count: coalesce(sum(fragment("if(? = 'write', 1, 0)", event.outcome)), 0),
          download_throughput_bytes:
            coalesce(
              sum(
                fragment(
                  "if(? = 'hit' AND ? > 0 AND ? > 0, ?, 0)",
                  event.outcome,
                  event.size,
                  event.duration_ms,
                  event.size
                )
              ),
              0
            ),
          download_throughput_duration_ms:
            coalesce(
              sum(
                fragment(
                  "if(? = 'hit' AND ? > 0 AND ? > 0, ?, 0)",
                  event.outcome,
                  event.size,
                  event.duration_ms,
                  event.duration_ms
                )
              ),
              0
            ),
          upload_throughput_bytes:
            coalesce(
              sum(
                fragment(
                  "if(? = 'write' AND ? > 0 AND ? > 0, ?, 0)",
                  event.outcome,
                  event.size,
                  event.duration_ms,
                  event.size
                )
              ),
              0
            ),
          upload_throughput_duration_ms:
            coalesce(
              sum(
                fragment(
                  "if(? = 'write' AND ? > 0 AND ? > 0, ?, 0)",
                  event.outcome,
                  event.size,
                  event.duration_ms,
                  event.duration_ms
                )
              ),
              0
            )
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn row ->
        lookups = numeric(row.hits) + numeric(row.misses)

        {row.date,
         %{
           hit_rate: if(lookups == 0, do: 0, else: Float.round(numeric(row.hits) / lookups * 100, 1)),
           lookups: lookups,
           download_bytes: numeric(row.download_bytes),
           upload_bytes: numeric(row.upload_bytes),
           read_latency_ms: divide(numeric(row.read_duration_ms), numeric(row.read_count)),
           write_latency_ms: divide(numeric(row.write_duration_ms), numeric(row.write_count)),
           latency_ms:
             divide(
               numeric(row.read_duration_ms) + numeric(row.write_duration_ms),
               numeric(row.read_count) + numeric(row.write_count)
             ),
           download_throughput_bytes_per_second:
             bytes_per_second(
               numeric(row.download_throughput_bytes),
               numeric(row.download_throughput_duration_ms)
             ),
           upload_throughput_bytes_per_second:
             bytes_per_second(
               numeric(row.upload_throughput_bytes),
               numeric(row.upload_throughput_duration_ms)
             )
         }}
      end)

    dates = start_datetime |> DateTime.to_date() |> Date.range(DateTime.to_date(end_datetime)) |> Enum.to_list()

    %{
      dates: dates,
      hit_rate_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).hit_rate),
      lookup_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).lookups),
      download_bytes_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).download_bytes),
      upload_bytes_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).upload_bytes),
      read_latency_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).read_latency_ms),
      write_latency_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).write_latency_ms),
      latency_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).latency_ms),
      download_throughput_values:
        Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).download_throughput_bytes_per_second),
      upload_throughput_values:
        Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).upload_throughput_bytes_per_second)
    }
  end

  def list_cache_events(project_id, flop_params \\ %{}) do
    CacheEvent
    |> where([event], event.project_id == ^project_id and event.operation == "action_cache")
    |> ClickHouseFlop.validate_and_run!(flop_params, for: CacheEvent)
  end

  def list_invocation_cache_events(project_id, invocation_id, flop_params \\ %{}) do
    normalized_invocation_id = String.downcase(invocation_id)

    CacheEvent
    |> where(
      [event],
      event.project_id == ^project_id and fragment("lower(?)", event.invocation_id) == ^normalized_invocation_id
    )
    |> ClickHouseFlop.validate_and_run!(flop_params, for: CacheEvent)
  end

  def list_invocation_cache_timeline_events(project_id, invocation_id) do
    normalized_invocation_id = String.downcase(invocation_id)

    ClickHouseRepo.all(
      from(event in CacheEvent,
        where: event.project_id == ^project_id and fragment("lower(?)", event.invocation_id) == ^normalized_invocation_id,
        order_by: [asc: event.observed_at],
        limit: @invocation_timeline_event_limit
      )
    )
  end

  def invocation_cache_outcome_counts(project_id, invocation_id) do
    normalized_invocation_id = String.downcase(invocation_id)

    CacheEvent
    |> where(
      [event],
      event.project_id == ^project_id and fragment("lower(?)", event.invocation_id) == ^normalized_invocation_id
    )
    |> group_by([event], event.outcome)
    |> select([event], %{outcome: event.outcome, count: count(event.id)})
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.outcome, &1.count})
    |> Map.merge(%{"hit" => 0, "miss" => 0, "write" => 0}, fn _outcome, count, _default -> count end)
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
    invocation_ids_by_normalized_value = Map.new(invocation_ids, &{String.downcase(&1), &1})
    normalized_invocation_ids = Map.keys(invocation_ids_by_normalized_value)

    rows =
      ClickHouseRepo.all(
        from(event in CacheEvent,
          where:
            event.project_id == ^project_id and event.operation == "action_cache" and
              fragment("lower(?)", event.invocation_id) in ^normalized_invocation_ids,
          group_by: fragment("lower(?)", event.invocation_id),
          select: %{
            invocation_id: fragment("lower(?)", event.invocation_id),
            hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", event.outcome)), 0),
            misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", event.outcome)), 0),
            writes: coalesce(sum(fragment("if(? = 'write', 1, 0)", event.outcome)), 0),
            download_bytes: coalesce(sum(fragment("if(? = 'hit', ?, 0)", event.outcome, event.size)), 0),
            upload_bytes: coalesce(sum(fragment("if(? = 'write', ?, 0)", event.outcome, event.size)), 0)
          }
        )
      )

    Map.new(rows, fn row ->
      lookups = row.hits + row.misses

      {Map.fetch!(invocation_ids_by_normalized_value, row.invocation_id),
       row
       |> Map.delete(:invocation_id)
       |> Map.put(:hit_rate, if(lookups == 0, do: nil, else: Float.round(row.hits / lookups * 100, 1)))}
    end)
  end

  def empty_summary do
    %{hits: 0, misses: 0, writes: 0, download_bytes: 0, upload_bytes: 0, hit_rate: nil}
  end

  defp cache_event_query(project_id, opts) do
    query =
      from(event in CacheEvent,
        where: event.project_id == ^project_id and event.operation == "action_cache"
      )

    case_result =
      case Keyword.get(opts, :start_datetime) do
        nil ->
          query

        start_datetime ->
          where(
            query,
            [event],
            event.inserted_at >= fragment("toDateTime(?, 'UTC')", ^datetime_string(start_datetime))
          )
      end

    then(case_result, fn query ->
      case Keyword.get(opts, :end_datetime) do
        nil ->
          query

        end_datetime ->
          where(
            query,
            [event],
            event.inserted_at < fragment("toDateTime(?, 'UTC')", ^datetime_string(end_datetime))
          )
      end
    end)
  end

  defp period(opts) do
    %{
      start_datetime: Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day)),
      end_datetime: Keyword.get(opts, :end_datetime, DateTime.utc_now())
    }
  end

  defp datetime_string(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp empty_summary_result do
    %{
      hits: 0,
      misses: 0,
      download_bytes: 0,
      upload_bytes: 0,
      read_duration_ms: 0,
      read_count: 0,
      write_duration_ms: 0,
      write_count: 0,
      download_throughput_bytes: 0,
      download_throughput_duration_ms: 0,
      upload_throughput_bytes: 0,
      upload_throughput_duration_ms: 0,
      last_observed_at: nil
    }
  end

  defp divide(_numerator, denominator) when denominator in [nil, 0], do: 0
  defp divide(nil, _denominator), do: 0
  defp divide(numerator, denominator), do: numeric(numerator) / numeric(denominator)
  defp bytes_per_second(_bytes, duration_ms) when duration_ms in [nil, 0], do: 0
  defp bytes_per_second(nil, _duration_ms), do: 0
  defp bytes_per_second(bytes, duration_ms), do: numeric(bytes) * 1000 / numeric(duration_ms)
  defp percentage(value), do: value |> numeric() |> Kernel.*(1.0) |> Float.round(1)

  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(nil), do: 0

  defp empty_analytics_row do
    %{
      hit_rate: 0,
      lookups: 0,
      download_bytes: 0,
      upload_bytes: 0,
      read_latency_ms: 0,
      write_latency_ms: 0,
      latency_ms: 0,
      download_throughput_bytes_per_second: 0,
      upload_throughput_bytes_per_second: 0
    }
  end
end
