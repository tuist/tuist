defmodule Tuist.ReapiCache do
  @moduledoc false

  import Ecto.Query

  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseTimeSeries
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache.CacheEvent

  @invocation_timeline_event_limit 500
  @ingest_pruning_slack_seconds 24 * 60 * 60
  @retention_days 90

  def invocation_timeline_event_limit, do: @invocation_timeline_event_limit

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

  def summary(project_id, options \\ []) when is_list(options) do
    query = cache_event_query(project_id, options)

    summary =
      ClickHouseRepo.one(
        from(event in query,
          select: %{
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
              ),
            last_observed_at: fragment("maxOrNull(?)", event.observed_at)
          }
        )
      )

    summary = summary || empty_summary_result()
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
    prune_start_datetime = DateTime.add(start_datetime, -@ingest_pruning_slack_seconds, :second)
    prune_end_datetime = DateTime.add(end_datetime, @ingest_pruning_slack_seconds, :second)

    query = """
    SELECT
      count() AS sample_count,
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
        AND inserted_at >= toDateTime({prune_start_datetime:String}, 'UTC')
        AND inserted_at < toDateTime({prune_end_datetime:String}, 'UTC')
        AND observed_at >= toDateTime({start_datetime:String}, 'UTC')
        AND observed_at < toDateTime({end_datetime:String}, 'UTC')
      GROUP BY invocation_id
      HAVING countIf(outcome IN ('hit', 'miss')) > 0
    )
    """

    {:ok, %{rows: [[sample_count, average, p99, p90, p50]]}} =
      ClickHouseRepo.query(query, %{
        project_id: project_id,
        start_datetime: datetime_string(start_datetime),
        end_datetime: datetime_string(end_datetime),
        prune_start_datetime: datetime_string(prune_start_datetime),
        prune_end_datetime: datetime_string(prune_end_datetime)
      })

    %{
      sample_count: sample_count,
      avg: percentage(average),
      p99: percentage(p99),
      p90: percentage(p90),
      p50: percentage(p50)
    }
  end

  def hit_rate_analytics(project_id, opts \\ []) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)
    granularity = ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
    date_format = ClickHouseTimeSeries.date_format(granularity)

    hit_rates =
      from(event in cache_event_query(project_id, opts),
        where: event.operation == "action_cache",
        group_by: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
        order_by: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
          hits: coalesce(sum(fragment("if(? = 'hit', 1, 0)", event.outcome)), 0),
          misses: coalesce(sum(fragment("if(? = 'miss', 1, 0)", event.outcome)), 0)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn %{date: date, hits: hits, misses: misses} ->
        lookups = hits + misses

        {date,
         %{
           hit_rate: if(lookups == 0, do: 0, else: Float.round(hits / lookups * 100, 1)),
           lookups: lookups
         }}
      end)

    dates = ClickHouseTimeSeries.buckets(start_datetime, end_datetime, granularity)

    %{
      dates: dates,
      values: Enum.map(dates, &Map.get(hit_rates, &1, %{hit_rate: 0}).hit_rate),
      lookup_values: Enum.map(dates, &Map.get(hit_rates, &1, %{lookups: 0}).lookups),
      hit_rate: summary(project_id, opts).hit_rate
    }
  end

  def analytics(project_id, opts \\ []) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)
    granularity = ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
    date_format = ClickHouseTimeSeries.date_format(granularity)

    rows =
      from(event in cache_event_query(project_id, opts),
        group_by: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
        order_by: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", event.observed_at, ^date_format),
          observations: count(event.id),
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
           observations: numeric(row.observations),
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
             bytes_per_second(numeric(row.download_throughput_bytes), numeric(row.download_throughput_duration_ms)),
           upload_throughput_bytes_per_second:
             bytes_per_second(numeric(row.upload_throughput_bytes), numeric(row.upload_throughput_duration_ms)),
           throughput_bytes_per_second:
             bytes_per_second(
               numeric(row.download_throughput_bytes) + numeric(row.upload_throughput_bytes),
               numeric(row.download_throughput_duration_ms) + numeric(row.upload_throughput_duration_ms)
             )
         }}
      end)

    dates = ClickHouseTimeSeries.buckets(start_datetime, end_datetime, granularity)

    %{
      dates: dates,
      observation_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).observations),
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
        Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).upload_throughput_bytes_per_second),
      throughput_values: Enum.map(dates, &Map.get(rows, &1, empty_analytics_row()).throughput_bytes_per_second)
    }
  end

  def observations_present?(project_id) do
    end_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(1, :second)

    project_id
    |> cache_event_ingest_query(
      start_datetime: NaiveDateTime.add(end_datetime, -@retention_days, :day),
      end_datetime: end_datetime
    )
    |> ClickHouseRepo.exists?()
  end

  def list_cache_events(project_id, flop_params \\ %{}, options \\ []) do
    project_id
    |> cache_event_query(options)
    |> ClickHouseFlop.validate_and_run!(flop_params, for: CacheEvent)
  end

  def list_invocation_cache_events(project_id, invocation_id, flop_params \\ %{}, options \\ []) do
    project_id
    |> invocation_cache_event_query(invocation_id, options)
    |> ClickHouseFlop.validate_and_run!(flop_params, for: CacheEvent)
  end

  def list_invocation_cache_timeline_events(project_id, invocation_id, options \\ []) do
    invocation_cache_timeline(project_id, invocation_id, options).events
  end

  def invocation_cache_timeline(project_id, invocation_id, options \\ []) do
    limit = Keyword.get(options, :limit, @invocation_timeline_event_limit)

    events =
      ClickHouseRepo.all(
        from(event in invocation_cache_event_query(project_id, invocation_id, options),
          order_by: [asc: event.observed_at],
          limit: ^(limit + 1)
        )
      )

    %{
      events: Enum.take(events, limit),
      limit: limit,
      truncated?: length(events) > limit
    }
  end

  def invocation_cache_outcome_counts(project_id, invocation_id, options \\ []) do
    project_id
    |> invocation_cache_event_query(invocation_id, options)
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

  def invocation_summary(project_id, invocation_id, options \\ []) do
    project_id
    |> invocation_summaries([invocation_id], options)
    |> Map.get(invocation_id, empty_summary())
  end

  def invocation_summaries(project_id, invocation_ids, options \\ [])

  def invocation_summaries(_project_id, [], _options), do: %{}

  def invocation_summaries(project_id, invocation_ids, options) do
    rows =
      ClickHouseRepo.all(
        from(event in cache_event_ingest_query(project_id, options),
          where: event.invocation_id in ^invocation_ids,
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

  defp cache_event_query(project_id, opts) do
    query = from(event in CacheEvent, where: event.project_id == ^project_id)

    query =
      case Keyword.get(opts, :start_datetime) do
        nil ->
          query

        start_datetime ->
          prune_start_datetime = shift_datetime(start_datetime, -@ingest_pruning_slack_seconds)

          where(
            query,
            [event],
            event.inserted_at >= ^prune_start_datetime and
              event.observed_at >= ^start_datetime
          )
      end

    case Keyword.get(opts, :end_datetime) do
      nil ->
        query

      end_datetime ->
        prune_end_datetime = shift_datetime(end_datetime, @ingest_pruning_slack_seconds)

        where(
          query,
          [event],
          event.inserted_at < ^prune_end_datetime and
            event.observed_at < ^end_datetime
        )
    end
  end

  defp cache_event_ingest_query(project_id, options) do
    query = from(event in CacheEvent, where: event.project_id == ^project_id)

    query =
      case Keyword.get(options, :start_datetime) do
        nil -> query
        start_datetime -> where(query, [event], event.inserted_at >= ^start_datetime)
      end

    case Keyword.get(options, :end_datetime) do
      nil -> query
      end_datetime -> where(query, [event], event.inserted_at < ^end_datetime)
    end
  end

  defp invocation_cache_event_query(project_id, invocation_id, options) do
    query =
      from(event in CacheEvent,
        where: event.project_id == ^project_id and event.invocation_id == ^invocation_id
      )

    query =
      case Keyword.get(options, :start_datetime) do
        nil -> query
        start_datetime -> where(query, [event], event.inserted_at >= ^start_datetime)
      end

    case Keyword.get(options, :end_datetime) do
      nil -> query
      end_datetime -> where(query, [event], event.inserted_at < ^end_datetime)
    end
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

  defp shift_datetime(%DateTime{} = datetime, seconds), do: DateTime.add(datetime, seconds, :second)
  defp shift_datetime(%NaiveDateTime{} = datetime, seconds), do: NaiveDateTime.add(datetime, seconds, :second)

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
      observations: 0,
      hit_rate: 0,
      lookups: 0,
      download_bytes: 0,
      upload_bytes: 0,
      read_latency_ms: 0,
      write_latency_ms: 0,
      latency_ms: 0,
      download_throughput_bytes_per_second: 0,
      upload_throughput_bytes_per_second: 0,
      throughput_bytes_per_second: 0
    }
  end
end
