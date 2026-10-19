defmodule Tuist.Cargo.Cache do
  @moduledoc "Project-scoped Cargo cache dashboard measurements, aggregated in ClickHouse."

  import Ecto.Query

  alias Tuist.Cargo.Build
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo

  @scatter_limit 10_000
  @retry_grace_seconds 86_400
  @recent_fields Build.__schema__(:fields) -- [:cache_metrics]
  @result_keys Map.new(
                 ~w(id inserted_at is_ci hit_rate avg p50 p90 p99 date downloaded_bytes uploaded_bytes read_ns write_ns reads writes download_ns upload_ns timed_download_bytes timed_upload_bytes)a,
                 &{Atom.to_string(&1), &1}
               )

  def hit_rate_analytics(project_id, opts) do
    current = rate_statistics(project_id, opts)
    previous = rate_statistics(project_id, previous_period(opts))

    series =
      rows(
        project_id,
        opts,
        "SELECT toDate(inserted_at) AS date, #{statistics_sql()} FROM rates GROUP BY date ORDER BY date"
      )

    %{metrics: current, trends: trends(current, previous), series: series}
  end

  defp rate_statistics(project_id, opts) do
    project_id |> rows(opts, "SELECT #{statistics_sql()} FROM rates") |> hd()
  end

  defp statistics_sql do
    "avgOrNull(hit_rate) AS avg, quantileExactOrNull(0.50)(hit_rate) AS p50, " <>
      "quantileExactOrNull(0.90)(hit_rate) AS p90, quantileExactOrNull(0.99)(hit_rate) AS p99"
  end

  def io_analytics(project_id, opts) do
    current = io_totals(project_id, opts)
    previous = io_totals(project_id, previous_period(opts))

    daily =
      rows(
        project_id,
        opts,
        "SELECT toDate(inserted_at) AS date, #{io_totals_sql()} FROM io GROUP BY date ORDER BY date"
      )

    Map.new(current, fn {widget, metrics} ->
      {widget,
       %{
         metrics: metrics,
         trends: trends(metrics, previous[widget]),
         series: Enum.map(daily, &Map.put(io_metrics(&1)[widget], :date, &1.date))
       }}
    end)
  end

  defp io_totals(project_id, opts) do
    project_id |> rows(opts, "SELECT #{io_totals_sql()} FROM io") |> hd() |> io_metrics()
  end

  defp io_totals_sql do
    Enum.map_join(
      ~w(downloaded_bytes uploaded_bytes read_ns write_ns reads writes download_ns upload_ns timed_download_bytes timed_upload_bytes),
      ", ",
      fn key ->
        "sumOrNull(#{key}) AS #{key}"
      end
    )
  end

  defp io_metrics(row) do
    %{
      transfer: %{
        "combined" => sum_available(row.downloaded_bytes, row.uploaded_bytes),
        "downloads" => row.downloaded_bytes,
        "uploads" => row.uploaded_bytes
      },
      latency: %{
        "combined" => average_ms(sum_available(row.read_ns, row.write_ns), sum_available(row.reads, row.writes)),
        "read" => average_ms(row.read_ns, row.reads),
        "write" => average_ms(row.write_ns, row.writes)
      },
      throughput: %{
        "combined" =>
          bytes_per_second(
            sum_available(row.timed_download_bytes, row.timed_upload_bytes),
            sum_available(row.download_ns, row.upload_ns)
          ),
        "downloads" => bytes_per_second(row.timed_download_bytes, row.download_ns),
        "uploads" => bytes_per_second(row.timed_upload_bytes, row.upload_ns)
      }
    }
  end

  def hit_rate_scatter_data(project_id, opts) do
    results =
      rows(
        project_id,
        opts,
        "SELECT toString(id) AS id, inserted_at, is_ci, hit_rate FROM rates ORDER BY inserted_at DESC, id DESC LIMIT #{@scatter_limit + 1}"
      )

    points = Enum.take(results, @scatter_limit)
    truncated = length(results) > @scatter_limit

    %{
      truncated: truncated,
      oldest_entry: if(truncated, do: List.last(points).inserted_at),
      series:
        points
        |> Enum.group_by(& &1.is_ci)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {is_ci, builds} ->
          %{
            name: is_ci,
            data:
              Enum.map(
                builds,
                &%{
                  id: &1.id,
                  value: [NaiveDateTime.diff(&1.inserted_at, ~N[1970-01-01 00:00:00], :millisecond), &1.hit_rate]
                }
              )
          }
        end)
    }
  end

  def recent_builds(project_id, opts) do
    start_datetime = opts |> Keyword.fetch!(:start_datetime) |> naive_datetime()
    end_datetime = opts |> Keyword.fetch!(:end_datetime) |> naive_datetime()
    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(50)
    retry_start_datetime = NaiveDateTime.add(start_datetime, -@retry_grace_seconds, :second)

    query =
      from(b in Build,
        where:
          b.project_id == ^project_id and b.command != "nextest" and b.inserted_at >= ^retry_start_datetime and
            b.inserted_at < ^end_datetime,
        distinct: b.id,
        order_by: [asc: b.inserted_at, asc: b.id],
        select: struct(b, ^@recent_fields)
      )

    query =
      case Keyword.get(opts, :is_ci) do
        value when is_boolean(value) -> where(query, [b], b.is_ci == ^value)
        _ -> query
      end

    builds =
      from(b in subquery(query),
        where: b.inserted_at >= ^start_datetime,
        order_by: [desc: b.inserted_at, desc: b.id],
        limit: ^limit,
        select: struct(b, ^@recent_fields)
      )
      |> ClickHouseRepo.all()
      |> Repo.preload(:ran_by_account)

    metrics = recent_metrics(builds, project_id, opts)

    Enum.map(builds, fn build ->
      %{build: build, cache: %{hit_rate: metrics[build.id], available: Map.has_key?(metrics, build.id)}}
    end)
  end

  defp recent_metrics([], _project_id, _opts), do: %{}

  defp recent_metrics(builds, project_id, opts) do
    project_id
    |> rows(
      opts,
      "SELECT toString(m.id) AS id, if(m.decisions > 0, 100.0 * m.hits / m.decisions, NULL) AS hit_rate FROM measured AS m WHERE m.id IN {build_ids:Array(UUID)}",
      %{build_ids: Enum.map(builds, & &1.id)}
    )
    |> Map.new(&{&1.id, &1.hit_rate})
  end

  def recent_hit_rate(rows) do
    rates = rows |> Enum.map(& &1.cache.hit_rate) |> Enum.reject(&is_nil/1)
    if rates != [], do: Enum.sum(rates) / length(rates)
  end

  defp rows(project_id, opts, sql, extra_params \\ %{}) do
    {environment, params} =
      case Keyword.get(opts, :is_ci) do
        value when is_boolean(value) -> {"AND is_ci = {is_ci:Bool}", %{is_ci: value}}
        _ -> {"", %{}}
      end

    params =
      params
      |> Map.merge(extra_params)
      |> Map.merge(%{
        project_id: project_id,
        start_datetime: opts |> Keyword.fetch!(:start_datetime) |> naive_datetime(),
        end_datetime: opts |> Keyword.fetch!(:end_datetime) |> naive_datetime()
      })

    result = ClickHouseRepo.query!(cohort_sql(environment) <> sql, params)
    keys = Enum.map(result.columns, &Map.fetch!(@result_keys, &1))
    Enum.map(result.rows, &Map.new(Enum.zip(keys, &1)))
  end

  defp cohort_sql(environment) do
    counters_valid =
      Enum.map_join(CacheMetrics.counters(), " AND ", fn key ->
        "(NOT mapContains(metric_fields, '#{key}') OR " <>
          "(JSONType(aggregate_json, '#{key}') IN ('Int64', 'UInt64') AND " <>
          "JSONExtractInt(metric_fields['#{key}']) BETWEEN 0 AND #{CacheMetrics.maximum()} AND " <>
          "JSONExtractUInt(metric_fields['#{key}']) <= #{CacheMetrics.maximum()}))"
      end)

    # Strip only an exact serialized inspection object, preserving original counter types.
    # Noncanonical inspection JSON falls back to validating the original document.
    """
    WITH versions AS (
      SELECT id, inserted_at, is_ci, cache_metrics FROM cargo_builds
      WHERE project_id = {project_id:Int64} AND command != 'nextest'
        AND inserted_at >= {start_datetime:DateTime} - INTERVAL #{@retry_grace_seconds} SECOND
        AND inserted_at < {end_datetime:DateTime}
        #{environment}
      ORDER BY inserted_at ASC, id ASC LIMIT 1 BY id
    ), builds AS (
      SELECT * FROM versions WHERE inserted_at >= {start_datetime:DateTime}
    ), parsed AS (
      SELECT *,
        JSONExtractRaw(cache_metrics, 'details') AS raw_details,
        if(JSONType(cache_metrics, 'details') = 'Object', replaceOne(cache_metrics, raw_details, 'null'), cache_metrics) AS aggregate_json,
        CAST(JSONExtractKeysAndValuesRaw(aggregate_json), 'Map(String, String)') AS metric_fields
      FROM builds WHERE length(cache_metrics) BETWEEN 1 AND 4100000 AND isValidJSON(cache_metrics)
    ), measured AS (
      SELECT *,
        JSONExtractUInt(metric_fields['hits']) AS hits,
        toFloat64(hits) + JSONExtractUInt(metric_fields['misses']) +
          JSONExtractUInt(metric_fields['unconsulted']) + JSONExtractUInt(metric_fields['verifications']) AS decisions
      FROM parsed
      WHERE JSONType(aggregate_json, 'version') IN ('Int64', 'UInt64')
        AND JSONExtractUInt(metric_fields['version']) = 1 AND #{counters_valid}
    ), rates AS (
      SELECT id, inserted_at, is_ci, 100.0 * hits / decisions AS hit_rate FROM measured WHERE decisions > 0
    ), details AS (
      SELECT *,
        CAST(JSONExtractKeysAndValuesRaw(raw_details), 'Map(String, String)') AS detail_fields,
        JSONExtractArrayRaw(detail_fields['tasks']) AS tasks,
        JSONExtractArrayRaw(detail_fields['cas_outputs']) AS cas_outputs
      FROM measured WHERE JSONExtractUInt(detail_fields['version']) = 1
    ), records AS (
      SELECT *,
        arrayFilter(x -> JSONType(x, 'read_duration_ns') IN ('Int64', 'UInt64')
          AND JSONExtractInt(x, 'read_duration_ns') BETWEEN 0 AND #{CacheMetrics.maximum()}, tasks) AS reads,
        arrayFilter(x -> JSONType(x, 'write_duration_ns') IN ('Int64', 'UInt64')
          AND JSONExtractInt(x, 'write_duration_ns') BETWEEN 0 AND #{CacheMetrics.maximum()}, tasks) AS writes,
        arrayFilter(x -> JSONExtractString(x, 'operation') = 'download' AND JSONExtractString(x, 'status') = 'downloaded'
          AND JSONExtractUInt(x, 'duration_ns') > 0, cas_outputs) AS downloads,
        arrayFilter(x -> JSONExtractString(x, 'operation') = 'upload' AND JSONExtractString(x, 'status') = 'uploaded'
          AND JSONExtractUInt(x, 'duration_ns') > 0, cas_outputs) AS uploads
      FROM details
    ), io AS (
      SELECT inserted_at,
        if(mapContains(metric_fields, 'downloaded_bytes'), toNullable(JSONExtractUInt(metric_fields['downloaded_bytes'])), NULL) AS downloaded_bytes,
        if(mapContains(metric_fields, 'uploaded_bytes'), toNullable(JSONExtractUInt(metric_fields['uploaded_bytes'])), NULL) AS uploaded_bytes,
        NULL AS read_ns, NULL AS write_ns, NULL AS reads, NULL AS writes,
        NULL AS download_ns, NULL AS upload_ns, NULL AS timed_download_bytes, NULL AS timed_upload_bytes
      FROM measured
      UNION ALL
      SELECT inserted_at, NULL, NULL,
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'read_duration_ns')), reads),
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'write_duration_ns')), writes), length(reads), length(writes),
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'duration_ns')), downloads),
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'duration_ns')), uploads),
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'size_bytes')), downloads),
        arraySum(x -> toFloat64(JSONExtractUInt(x, 'size_bytes')), uploads)
      FROM records
    )
    """
  end

  defp previous_period(opts) do
    start_datetime = opts |> Keyword.fetch!(:start_datetime) |> naive_datetime()
    end_datetime = opts |> Keyword.fetch!(:end_datetime) |> naive_datetime()
    seconds = NaiveDateTime.diff(end_datetime, start_datetime, :second)

    opts
    |> Keyword.put(:start_datetime, NaiveDateTime.add(start_datetime, -seconds, :second))
    |> Keyword.put(:end_datetime, start_datetime)
  end

  defp trends(current, previous), do: Map.new(current, fn {key, value} -> {key, trend(value, previous[key])} end)
  defp trend(nil, _), do: nil
  defp trend(_, nil), do: nil
  defp trend(current, previous) when previous > 0, do: (current - previous) / previous * 100
  defp trend(current, previous) when current == 0 and previous == 0, do: 0
  defp trend(_, _), do: nil
  defp naive_datetime(%DateTime{} = value), do: DateTime.to_naive(value)
  defp naive_datetime(value), do: value
  defp sum_available(nil, nil), do: nil
  defp sum_available(left, right), do: (left || 0) + (right || 0)

  defp average_ms(duration, count) when is_number(duration) and is_number(count) and count > 0,
    do: duration / count / 1_000_000

  defp average_ms(_, _), do: nil

  defp bytes_per_second(bytes, duration) when is_number(bytes) and is_number(duration) and duration > 0,
    do: bytes * 1_000_000_000 / duration

  defp bytes_per_second(_, _), do: nil
end
