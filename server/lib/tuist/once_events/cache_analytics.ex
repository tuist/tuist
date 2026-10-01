defmodule Tuist.OnceEvents.CacheAnalytics do
  @moduledoc """
  Bazel-cache-shaped analytics for Once runs.

  The Once Cache page reuses `TuistWeb.BazelCacheLive`'s layout, so
  this module exposes the same functions and return shapes as
  `Tuist.ReapiCache`, only sourced from Once tables
  (`once_runs`, `once_actions`, `once_cache_events`) instead of the
  REAPI observation store.
  """

  import Ecto.Query

  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.CacheEvent
  alias Tuist.OnceEvents.Run
  alias Tuist.Repo

  @doc """
  Aggregate cache totals over a project + period. Same shape as
  `Tuist.ReapiCache.summary/2` so the shared Cache LiveView reads
  the fields without translation.
  """
  def summary(project_id, opts \\ []) do
    {start_dt, end_dt} = period_datetimes(opts)

    action_stats =
      Action
      |> where([a], a.project_id == ^project_id and a.capability != "_phase")
      |> join(:inner, [a], r in Run, on: r.id == a.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> select([a, _], %{
        read_ms:
          fragment(
            "coalesce(avg(case when ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        write_ms:
          fragment(
            "coalesce(avg(case when not ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        avg_ms: fragment("coalesce(avg(?), 0)", a.duration_ms),
        # Totals feed the throughput denominators below. Averages
        # answer "how slow was one probe on average"; sums answer
        # "how much wall time was spent probing" which is what
        # throughput divides by.
        read_ms_total:
          fragment(
            "coalesce(sum(case when ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        write_ms_total:
          fragment(
            "coalesce(sum(case when not ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          )
      })
      |> Repo.one() ||
        %{
          read_ms: 0,
          write_ms: 0,
          avg_ms: 0,
          read_ms_total: 0,
          write_ms_total: 0
        }

    transfer_row =
      CacheEvent
      |> where([e], e.project_id == ^project_id)
      |> join(:inner, [e], r in Run, on: r.id == e.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> maybe_filter_run_environment(opts)
      |> select([e, _], %{
        download_bytes:
          fragment(
            "coalesce(sum(case when ? = 'download' then ? end), 0)",
            e.kind,
            e.bytes_transferred
          ),
        upload_bytes:
          fragment(
            "coalesce(sum(case when ? = 'upload' then ? end), 0)",
            e.kind,
            e.bytes_transferred
          ),
        download_ms:
          fragment(
            "coalesce(sum(case when ? = 'download' then ? end), 0)",
            e.kind,
            e.duration_ms
          ),
        upload_ms:
          fragment(
            "coalesce(sum(case when ? = 'upload' then ? end), 0)",
            e.kind,
            e.duration_ms
          )
      })
      |> Repo.one() || %{download_bytes: 0, upload_bytes: 0, download_ms: 0, upload_ms: 0}

    download_bytes = to_int(transfer_row.download_bytes)
    upload_bytes = to_int(transfer_row.upload_bytes)
    transfer_bytes = download_bytes + upload_bytes

    read_latency_ms = to_int(action_stats.read_ms)
    write_latency_ms = to_int(action_stats.write_ms)
    latency_ms = to_int(action_stats.avg_ms)

    # The client doesn't measure per-blob wall time yet, so
    # `once_cache_events.duration_ms` is ~0 and dividing by it
    # produces the useless "No data yet" placeholder. Fall back to
    # the total action-cache probe time (read for downloads, write
    # for uploads) as the denominator — real wall time the runner
    # spent on cache traffic, close enough to the Bazel throughput
    # story until we instrument per-blob timing on the client.
    read_ms_total = to_int(action_stats.read_ms_total)
    write_ms_total = to_int(action_stats.write_ms_total)

    download_throughput = safe_throughput(download_bytes, read_ms_total)
    upload_throughput = safe_throughput(upload_bytes, write_ms_total)

    total_throughput =
      safe_throughput(transfer_bytes, read_ms_total + write_ms_total)

    %{
      transfer_bytes: transfer_bytes,
      download_bytes: download_bytes,
      upload_bytes: upload_bytes,
      latency_ms: latency_ms,
      read_latency_ms: read_latency_ms,
      write_latency_ms: write_latency_ms,
      throughput_bytes_per_second: total_throughput,
      download_throughput_bytes_per_second: download_throughput,
      upload_throughput_bytes_per_second: upload_throughput
    }
  end

  @scatter_data_limit 1000

  @doc """
  One point per finalized run: its action-cache hit rate against when it
  started, grouped for the scatter chart. `:group_by` is `:host` or
  `:version`, the two dimensions a Once run records that are worth
  splitting on, and the shape matches what `TuistWeb.Components.ScatterChart`
  expects.
  """
  def hit_rate_scatter_data(project_id, opts \\ []) do
    {start_dt, end_dt} = period_datetimes(opts)
    group_by = Keyword.get(opts, :group_by, :host)

    runs =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> where([r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> maybe_filter_environment(opts)
      |> where([r], r.total_actions > 0)
      |> order_by([r], desc: r.started_at)
      |> limit(^@scatter_data_limit)
      |> select([r], %{
        run_id: r.run_id,
        started_at: r.started_at,
        host_class: r.host_class,
        once_version: r.once_version,
        kind: r.kind,
        value: fragment("(?::float / ?) * 100.0", r.cached_actions, r.total_actions)
      })
      |> Repo.all()

    scatter_result(runs, group_by)
  end

  @doc """
  Per-invocation cache-hit-rate distribution over the selected
  period. Same map shape as `Tuist.ReapiCache.invocation_hit_rate_metrics/2`.
  """
  def invocation_hit_rate_metrics(project_id, opts \\ []) do
    {start_dt, end_dt} = period_datetimes(opts)

    rates =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> where([r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> where([r], r.total_actions > 0)
      |> select([r], fragment("(?::float / ?) * 100.0", r.cached_actions, r.total_actions))
      |> Repo.all()
      |> Enum.map(&to_float/1)
      |> Enum.sort()

    count = length(rates)

    if count == 0 do
      %{avg: 0.0, p50: 0.0, p90: 0.0, p99: 0.0, sample_count: 0}
    else
      %{
        avg: Float.round(Enum.sum(rates) / count, 1),
        p50: percentile(rates, 0.5),
        p90: percentile(rates, 0.9),
        p99: percentile(rates, 0.99),
        sample_count: count
      }
    end
  end

  @doc """
  True if the project has any once cache activity ever (any action
  cache probe or any content transfer). Drives the "no data yet"
  empty state on the Cache page.
  """
  def observations_present?(project_id) do
    action_present =
      Action
      |> where([a], a.project_id == ^project_id and a.capability != "_phase")
      |> limit(1)
      |> Repo.aggregate(:count, :id)

    action_present > 0 or
      CacheEvent
      |> where([e], e.project_id == ^project_id)
      |> limit(1)
      |> Repo.aggregate(:count, :id) > 0
  end

  @doc """
  Time-bucketed series over the selected period. Same shape as
  `Tuist.ReapiCache.analytics/2`: `dates` + one series per widget the
  page renders.
  """
  def analytics(project_id, opts \\ []) do
    {start_dt, end_dt} = period_datetimes(opts)
    granularity = granularity_for(start_dt, end_dt)

    action_rows =
      Action
      |> where([a], a.project_id == ^project_id and a.capability != "_phase")
      |> join(:inner, [a], r in Run, on: r.id == a.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> maybe_filter_run_environment(opts)
      |> group_by([a, r], fragment("date_trunc(?, ?)", ^to_string(granularity), r.started_at))
      |> select([a, r], %{
        bucket: fragment("min(?)", r.started_at),
        lookups: count(a.id),
        hits: sum(fragment("(case when ? then 1 else 0 end)", a.was_cached)),
        read_ms:
          fragment(
            "coalesce(avg(case when ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        write_ms:
          fragment(
            "coalesce(avg(case when not ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        read_ms_total:
          fragment(
            "coalesce(sum(case when ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        write_ms_total:
          fragment(
            "coalesce(sum(case when not ? then ? end), 0)",
            a.was_cached,
            a.duration_ms
          ),
        latency_ms: fragment("coalesce(avg(?), 0)", a.duration_ms)
      })
      |> Repo.all()

    transfer_rows =
      CacheEvent
      |> where([e], e.project_id == ^project_id)
      |> join(:inner, [e], r in Run, on: r.id == e.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> group_by([e, r], fragment("date_trunc(?, ?)", ^to_string(granularity), r.started_at))
      |> select([e, r], %{
        bucket: fragment("min(?)", r.started_at),
        observations: count(e.id),
        download_bytes: fragment("coalesce(sum(case when ? = 'download' then ? end), 0)", e.kind, e.bytes_transferred),
        upload_bytes: fragment("coalesce(sum(case when ? = 'upload' then ? end), 0)", e.kind, e.bytes_transferred),
        download_ms: fragment("coalesce(sum(case when ? = 'download' then ? end), 0)", e.kind, e.duration_ms),
        upload_ms: fragment("coalesce(sum(case when ? = 'upload' then ? end), 0)", e.kind, e.duration_ms)
      })
      |> Repo.all()

    actions_by_bucket = Map.new(action_rows, &{bucket_key(&1.bucket, granularity), &1})
    transfers_by_bucket = Map.new(transfer_rows, &{bucket_key(&1.bucket, granularity), &1})

    dates = bucket_range(start_dt, end_dt, granularity)

    series =
      Enum.map(dates, fn key ->
        a = Map.get(actions_by_bucket, key)
        t = Map.get(transfers_by_bucket, key)
        build_series_row(a, t)
      end)

    %{
      dates: dates,
      lookup_values: Enum.map(series, & &1.lookups),
      observation_values: Enum.map(series, & &1.observations),
      hit_rate_values: Enum.map(series, & &1.hit_rate),
      download_bytes_values: Enum.map(series, & &1.download_bytes),
      upload_bytes_values: Enum.map(series, & &1.upload_bytes),
      latency_values: Enum.map(series, & &1.latency_ms),
      read_latency_values: Enum.map(series, & &1.read_ms),
      write_latency_values: Enum.map(series, & &1.write_ms),
      throughput_values: Enum.map(series, & &1.throughput),
      download_throughput_values: Enum.map(series, & &1.download_throughput),
      upload_throughput_values: Enum.map(series, & &1.upload_throughput)
    }
  end

  @doc """
  Most recent Once runs that ended in the given period, shaped as
  the Bazel Cache page's `recent_invocations` — each row carries
  `invocation_id`, `command`, `target_patterns`, `duration_ms`,
  `finished_at`, `account_handle`, and a `cache` sub-map with
  `hit_rate`, `download_bytes`, `upload_bytes`.
  """
  def recent_invocations(project_id, opts \\ []) do
    {start_dt, end_dt} = period_datetimes(opts)
    limit = Keyword.get(opts, :limit, 40)

    Run
    |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
    |> where([r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
    |> order_by([r], desc: r.finalized_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&run_to_invocation/1)
  end

  # ---- Internals --------------------------------------------------------

  defp build_series_row(action_row, transfer_row) do
    lookups = bucket_value(action_row, :lookups)
    hits = bucket_value(action_row, :hits)
    read_ms_total = bucket_value(action_row, :read_ms_total)
    write_ms_total = bucket_value(action_row, :write_ms_total)

    download_bytes = bucket_value(transfer_row, :download_bytes)
    upload_bytes = bucket_value(transfer_row, :upload_bytes)

    # Throughput denominators: action-cache probe time (per-blob
    # wall time isn't measured on the client yet, so
    # `once_cache_events.duration_ms` is ~0). See summary/2.
    %{
      lookups: lookups,
      observations: bucket_value(transfer_row, :observations),
      hit_rate: percentage(hits, lookups),
      download_bytes: download_bytes,
      upload_bytes: upload_bytes,
      latency_ms: bucket_value(action_row, :latency_ms),
      read_ms: bucket_value(action_row, :read_ms),
      write_ms: bucket_value(action_row, :write_ms),
      throughput: safe_throughput(download_bytes + upload_bytes, read_ms_total + write_ms_total),
      download_throughput: safe_throughput(download_bytes, read_ms_total),
      upload_throughput: safe_throughput(upload_bytes, write_ms_total)
    }
  end

  # A bucket with no rows on one side of the join is absent, not zeroed.
  defp bucket_value(nil, _key), do: 0
  defp bucket_value(row, key), do: row |> Map.fetch!(key) |> to_int()

  defp percentage(_part, 0), do: 0.0
  defp percentage(part, whole), do: Float.round(part / whole * 100.0, 1)

  defp run_to_invocation(%Run{} = run) do
    hits = run.cached_actions || 0
    total = run.total_actions || 0

    hit_rate =
      if total > 0 do
        Float.round(hits / total * 100.0, 1)
      end

    %{
      invocation_id: run.run_id,
      command: display_command(run),
      target_patterns: [],
      duration_ms: run.wall_ms || 0,
      finished_at: run.finalized_at || run.started_at,
      is_ci: run.is_ci || false,
      account_handle: nil,
      cache: %{
        hit_rate: hit_rate,
        download_bytes: run.cache_bytes_downloaded || 0,
        upload_bytes: run.cache_bytes_uploaded || 0
      }
    }
  end

  defp display_command(run) do
    cond do
      is_binary(run.command_display) and run.command_display != "" -> run.command_display
      is_binary(run.kind) and run.kind != "" -> "once " <> run.kind
      true -> "once"
    end
  end

  defp period_datetimes(opts) do
    case {Keyword.get(opts, :start_datetime), Keyword.get(opts, :end_datetime)} do
      {%DateTime{} = s, %DateTime{} = e} ->
        {s, e}

      _ ->
        end_dt = DateTime.utc_now()
        {DateTime.add(end_dt, -30 * 86_400, :second), end_dt}
    end
  end

  defp granularity_for(start_dt, end_dt) do
    diff_hours = DateTime.diff(end_dt, start_dt, :second) / 3600
    if diff_hours <= 48, do: :hour, else: :day
  end

  defp bucket_range(start_dt, end_dt, :day) do
    start_date = DateTime.to_date(start_dt)
    end_date = DateTime.to_date(end_dt)
    start_date |> Date.range(end_date) |> Enum.map(&Date.to_iso8601/1)
  end

  defp bucket_range(start_dt, end_dt, :hour) do
    start_dt = %{start_dt | minute: 0, second: 0, microsecond: {0, 0}}
    end_dt = %{end_dt | minute: 0, second: 0, microsecond: {0, 0}}
    diff = end_dt |> DateTime.diff(start_dt, :second) |> div(3600)

    Enum.map(0..diff, fn h ->
      start_dt |> DateTime.add(h * 3600, :second) |> DateTime.to_iso8601()
    end)
  end

  defp bucket_key(%DateTime{} = dt, :day), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp bucket_key(%DateTime{} = dt, :hour), do: DateTime.to_iso8601(%{dt | minute: 0, second: 0, microsecond: {0, 0}})

  defp bucket_key(%NaiveDateTime{} = ndt, granularity) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> bucket_key(granularity)
  end

  defp bucket_key(_, _), do: nil

  defp percentile([], _p), do: 0.0

  defp percentile(sorted, p) do
    idx = min(round(p * (length(sorted) - 1)), length(sorted) - 1)
    sorted |> Enum.at(idx) |> Float.round(1)
  end

  defp safe_throughput(_bytes, 0), do: 0
  defp safe_throughput(bytes, ms) when ms > 0, do: div(bytes * 1000, ms)
  defp safe_throughput(_, _), do: 0

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(Decimal.round(d, 0))
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)
  defp to_int(_), do: 0

  # `:is_ci` is the opt `Tuist.OnceEvents.Analytics` filters on, so the
  # Environment control means the same thing on every Once card.
  defp maybe_filter_environment(query, opts) do
    case Keyword.get(opts, :is_ci) do
      is_ci when is_boolean(is_ci) -> where(query, [r], r.is_ci == ^is_ci)
      _ -> query
    end
  end

  # Same filter where the run is the joined binding rather than the first.
  defp maybe_filter_run_environment(query, opts) do
    case Keyword.get(opts, :is_ci) do
      is_ci when is_boolean(is_ci) -> where(query, [_, r], r.is_ci == ^is_ci)
      _ -> query
    end
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(_), do: 0.0

  # `ScatterChart` wants `%{series: [%{name, data: [%{value: [ts_ms, y], id, meta}]}],
  # truncated, oldest_entry}`; the limit above is what `truncated` reports on.
  defp scatter_result(runs, group_by) do
    truncated = length(runs) >= @scatter_data_limit

    series =
      runs
      |> Enum.group_by(&scatter_group(&1, group_by))
      |> Enum.map(fn {group, grouped} ->
        %{
          name: group,
          data:
            Enum.map(grouped, fn run ->
              %{
                value: [DateTime.to_unix(run.started_at, :millisecond), round_value(run.value)],
                id: run.run_id,
                meta: %{host: run.host_class, version: run.once_version, kind: run.kind}
              }
            end)
        }
      end)

    %{
      series: series,
      truncated: truncated,
      oldest_entry: if(truncated, do: runs |> List.last() |> Map.get(:started_at))
    }
  end

  defp scatter_group(run, :version), do: presence(run.once_version, "Unknown version")
  defp scatter_group(run, _host), do: presence(run.host_class, "Unknown host")

  defp presence(value, _fallback) when is_binary(value) and value != "", do: value
  defp presence(_value, fallback), do: fallback

  defp round_value(value) when is_float(value), do: Float.round(value, 1)
  defp round_value(value), do: value
end
