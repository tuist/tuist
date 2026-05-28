defmodule Tuist.Kura.Usage do
  @moduledoc """
  Persists and queries Kura node usage rollups.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Projects

  @max_events_per_batch 5_000

  # Kura's wire format uses tenant_id/namespace_id (it's tenant-agnostic). We
  # resolve them to Tuist account/project ids at the boundary and persist only
  # the ids — anything that can't be resolved drops to 0 and is treated as
  # unattributable traffic.
  def create_events(events) when is_list(events) and length(events) <= @max_events_per_batch do
    projects_by_handle = lookup_projects(events)
    account_ids_by_handle = lookup_account_ids(events)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows = Enum.map(events, &build_row(&1, projects_by_handle, account_ids_by_handle, now))

    if rows != [] do
      IngestRepo.insert_all(UsageEvent, rows)
    end

    {:ok, length(rows)}
  end

  def create_events(events) when is_list(events), do: {:error, :too_many_events}

  defp lookup_projects(events) do
    events
    |> Enum.map(&"#{&1["tenant_id"]}/#{&1["namespace_id"]}")
    |> Enum.uniq()
    |> Projects.projects_by_full_handles()
  end

  defp lookup_account_ids(events) do
    events
    |> Enum.map(& &1["tenant_id"])
    |> Accounts.get_account_ids_by_handles()
  end

  defp build_row(event, projects_by_handle, account_ids_by_handle, now) do
    account_handle = event["tenant_id"]
    project_handle = event["namespace_id"]
    full_handle = "#{account_handle}/#{project_handle}"
    project = Map.get(projects_by_handle, full_handle)

    %{
      event_id: event["event_id"],
      account_id: resolve_account_id(project, account_ids_by_handle, account_handle),
      project_id: resolve_project_id(project),
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
  end

  defp resolve_account_id(nil, account_ids_by_handle, account_handle),
    do: Map.get(account_ids_by_handle, account_handle) || 0

  defp resolve_account_id(%{account_id: account_id}, _account_ids_by_handle, _account_handle),
    do: account_id

  defp resolve_project_id(nil), do: 0
  defp resolve_project_id(%{id: id}), do: id

  defp unix_seconds_to_naive_datetime(seconds) when is_integer(seconds) do
    seconds
    |> DateTime.from_unix!()
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  @doc """
  Totals broken down by direction (egress + ingress) for an account in
  `[start_dt, end_dt]`, plus a trend (% change) versus the equivalent
  previous window so the dashboard widgets can show "since last week" /
  "since yesterday" deltas. Pass `:project_id` to scope to a single
  project.

  Returns `%{egress: %{bytes, bytes_trend, request_count},
  ingress: %{bytes, bytes_trend, request_count}, request_count,
  request_count_trend}`.
  """
  def totals(account_id, start_dt, end_dt, opts \\ []) when is_integer(account_id) do
    current = totals_in_range(account_id, start_dt, end_dt, opts)
    {prev_start, prev_end} = previous_window(start_dt, end_dt)
    previous = totals_in_range(account_id, prev_start, prev_end, opts)

    %{
      egress: %{
        bytes: current.egress.bytes,
        request_count: current.egress.request_count,
        bytes_trend: trend(previous.egress.bytes, current.egress.bytes)
      },
      ingress: %{
        bytes: current.ingress.bytes,
        request_count: current.ingress.request_count,
        bytes_trend: trend(previous.ingress.bytes, current.ingress.bytes)
      },
      request_count: current.request_count,
      request_count_trend: trend(previous.request_count, current.request_count)
    }
  end

  defp totals_in_range(account_id, start_dt, end_dt, opts) do
    rows =
      ClickHouseRepo.all(
        from(e in subquery(deduped_event_query(account_id, start_dt, end_dt, opts)),
          group_by: e.direction,
          select: %{
            direction: e.direction,
            bytes: fragment("sum(?)", e.bytes),
            request_count: fragment("sum(?)", e.request_count)
          }
        )
      )

    egress = find_direction_row(rows, "egress")
    ingress = find_direction_row(rows, "ingress")

    %{
      egress: egress,
      ingress: ingress,
      request_count: egress.request_count + ingress.request_count
    }
  end

  defp find_direction_row(rows, direction) do
    case Enum.find(rows, &(&1.direction == direction)) do
      nil -> %{bytes: 0, request_count: 0}
      row -> %{bytes: zeroed(row.bytes), request_count: zeroed(row.request_count)}
    end
  end

  @doc """
  Per-node traffic breakdown within `[start_dt, end_dt]`. Returns one row per
  `(node_id, region)` with egress + ingress bytes and request totals, sorted
  by total bytes desc.
  """
  def per_node(account_id, start_dt, end_dt, opts \\ []) when is_integer(account_id) do
    rows =
      ClickHouseRepo.all(
        from(e in subquery(deduped_event_query(account_id, start_dt, end_dt, opts)),
          group_by: [e.node_id, e.region, e.direction],
          select: %{
            node_id: e.node_id,
            region: e.region,
            direction: e.direction,
            bytes: fragment("sum(?)", e.bytes),
            request_count: fragment("sum(?)", e.request_count)
          }
        )
      )

    rows
    |> Enum.group_by(fn r -> {r.node_id, r.region} end)
    |> Enum.map(fn {{node_id, region}, direction_rows} ->
      egress =
        Enum.find(direction_rows, &(&1.direction == "egress")) || %{bytes: 0, request_count: 0}

      ingress =
        Enum.find(direction_rows, &(&1.direction == "ingress")) || %{bytes: 0, request_count: 0}

      %{
        node_id: node_id,
        region: region,
        egress_bytes: zeroed(egress.bytes),
        ingress_bytes: zeroed(ingress.bytes),
        request_count: zeroed(egress.request_count) + zeroed(ingress.request_count)
      }
    end)
    |> Enum.sort_by(&(&1.egress_bytes + &1.ingress_bytes), :desc)
  end

  @doc """
  Time series per `bucket` (`:hour` or `:day`) within the window, broken
  down by `region`. Returns a list of `%{region, dates, values, total}` — one
  per region with traffic. Buckets without traffic are filled with zero so
  each series shares the same x-axis.

  Options:
    * `:metric` — `:bytes` (default) or `:requests`. Controls which column is
      summed into the series values.
    * `:direction` — `"egress"` or `"ingress"` to scope the series.
    * `:project_id` — scope to a single project.
  """
  def traffic_time_series_by_region(account_id, start_dt, end_dt, opts \\ [])
      when is_integer(account_id) do
    bucket = Keyword.get(opts, :bucket, :day)
    metric = Keyword.get(opts, :metric, :bytes)
    rows = traffic_per_bucket_by_region(account_id, start_dt, end_dt, opts, bucket, metric)
    dates = bucket_seq(start_dt, end_dt, bucket)

    rows
    |> Enum.group_by(& &1.region)
    |> Enum.map(fn {region, region_rows} ->
      by_key = Map.new(region_rows, fn %{date: d, value: v} -> {bucket_key(d), zeroed(v)} end)
      values = Enum.map(dates, fn key -> Map.get(by_key, key, 0) end)
      total = Enum.sum(values)
      %{region: region, dates: dates, values: values, total: total}
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  defp traffic_per_bucket_by_region(account_id, start_dt, end_dt, opts, :hour, metric) do
    from(e in subquery(deduped_event_query(account_id, start_dt, end_dt, opts)),
      group_by: [fragment("toStartOfHour(?)", e.window_start), e.region],
      order_by: fragment("toStartOfHour(?)", e.window_start)
    )
    |> select_metric_series(metric, :hour)
    |> ClickHouseRepo.all()
  end

  defp traffic_per_bucket_by_region(account_id, start_dt, end_dt, opts, :day, metric) do
    from(e in subquery(deduped_event_query(account_id, start_dt, end_dt, opts)),
      group_by: [fragment("toDate(?)", e.window_start), e.region],
      order_by: fragment("toDate(?)", e.window_start)
    )
    |> select_metric_series(metric, :day)
    |> ClickHouseRepo.all()
  end

  defp select_metric_series(query, :bytes, :hour) do
    select(query, [e], %{
      date: fragment("toStartOfHour(?)", e.window_start),
      region: e.region,
      value: fragment("sum(?)", e.bytes)
    })
  end

  defp select_metric_series(query, :bytes, :day) do
    select(query, [e], %{
      date: fragment("toDate(?)", e.window_start),
      region: e.region,
      value: fragment("sum(?)", e.bytes)
    })
  end

  defp select_metric_series(query, :requests, :hour) do
    select(query, [e], %{
      date: fragment("toStartOfHour(?)", e.window_start),
      region: e.region,
      value: fragment("sum(?)", e.request_count)
    })
  end

  defp select_metric_series(query, :requests, :day) do
    select(query, [e], %{
      date: fragment("toDate(?)", e.window_start),
      region: e.region,
      value: fragment("sum(?)", e.request_count)
    })
  end

  @doc """
  Distinct project IDs that produced at least one usage event for the account.
  Used to populate the project filter dropdown without listing projects that
  have never seen Kura traffic.
  """
  def project_ids_with_usage(account_id) when is_integer(account_id) do
    ClickHouseRepo.all(
      from(e in UsageEvent,
        where: e.account_id == ^account_id and e.project_id > 0,
        group_by: e.project_id,
        select: e.project_id
      )
    )
  end

  # Dedupes the raw event stream by `event_id`, picking the latest version of
  # each column via argMax(column, inserted_at). Kura delivers usage events
  # at-least-once and the ReplacingMergeTree only collapses duplicates at merge
  # time, so aggregating directly over the table risks counting a retried
  # event_id twice. Every aggregation in this module sits on top of this
  # subquery so retries can't inflate customer-visible usage.
  defp deduped_event_query(account_id, start_dt, end_dt, opts) do
    start_naive = to_naive(start_dt)
    end_naive = to_naive(end_dt)

    base =
      from(e in UsageEvent,
        where:
          e.account_id == ^account_id and
            e.window_start >= ^start_naive and
            e.window_start <= ^end_naive
      )
      |> maybe_project_filter(Keyword.get(opts, :project_id))
      |> maybe_direction_filter(Keyword.get(opts, :direction))

    from(e in base,
      group_by: e.event_id,
      select: %{
        project_id: fragment("argMax(?, ?)", e.project_id, e.inserted_at),
        direction: fragment("argMax(?, ?)", e.direction, e.inserted_at),
        node_id: fragment("argMax(?, ?)", e.node_id, e.inserted_at),
        region: fragment("argMax(?, ?)", e.region, e.inserted_at),
        window_start: fragment("argMax(?, ?)", e.window_start, e.inserted_at),
        bytes: fragment("argMax(?, ?)", e.bytes, e.inserted_at),
        request_count: fragment("argMax(?, ?)", e.request_count, e.inserted_at)
      }
    )
  end

  defp maybe_project_filter(query, nil), do: query

  defp maybe_project_filter(query, project_id) when is_integer(project_id),
    do: from(e in query, where: e.project_id == ^project_id)

  defp maybe_direction_filter(query, nil), do: query

  defp maybe_direction_filter(query, direction) when direction in ["egress", "ingress"],
    do: from(e in query, where: e.direction == ^direction)

  # The previous window is the same length as the current one, ending where
  # the current one begins. Matches the convention `Tuist.Runners.Analytics`
  # uses for "since last week" / "since yesterday" trend badges.
  defp previous_window(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    seconds = DateTime.diff(end_dt, start_dt, :second)
    {DateTime.add(start_dt, -seconds, :second), start_dt}
  end

  defp trend(previous, current) when is_number(previous) and is_number(current) do
    cond do
      previous == 0 -> 0.0
      current == 0 -> 0.0
      true -> Float.round(current / previous * 100, 1) - 100.0
    end
  end

  defp trend(_, _), do: 0.0

  defp to_naive(%DateTime{} = dt),
    do: dt |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

  defp to_naive(%NaiveDateTime{} = nd), do: NaiveDateTime.truncate(nd, :second)

  defp zeroed(nil), do: 0
  defp zeroed(%Decimal{} = d), do: Decimal.to_integer(d)
  defp zeroed(n) when is_integer(n), do: n
  defp zeroed(n) when is_float(n), do: trunc(n)

  defp bucket_key(%DateTime{} = dt), do: DateTime.to_naive(dt)
  defp bucket_key(%NaiveDateTime{} = nd), do: nd
  defp bucket_key(%Date{} = d), do: d

  defp bucket_seq(start_dt, end_dt, :day) do
    start_date = dt_to_date(start_dt)
    end_date = dt_to_date(end_dt)
    start_date |> Date.range(end_date) |> Enum.to_list()
  end

  defp bucket_seq(start_dt, end_dt, :hour) do
    start_naive = start_dt |> to_naive() |> truncate_to_hour()
    end_naive = end_dt |> to_naive() |> truncate_to_hour()

    start_naive
    |> Stream.unfold(fn current ->
      if NaiveDateTime.after?(current, end_naive) do
        nil
      else
        {current, NaiveDateTime.add(current, 3600, :second)}
      end
    end)
    |> Enum.to_list()
  end

  defp dt_to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp dt_to_date(%NaiveDateTime{} = nd), do: NaiveDateTime.to_date(nd)

  defp truncate_to_hour(%NaiveDateTime{} = nd) do
    %{nd | minute: 0, second: 0, microsecond: {0, 0}}
  end
end
