defmodule Tuist.OnceEvents.Analytics do
  @moduledoc """
  Bazel-shaped analytics for Once runs.

  The Once builds page reuses the same layout as the Bazel builds page
  (`TuistWeb.BazelInvocationsLive`), so this module exposes functions
  whose signatures and return shapes mirror `Tuist.Bazel`'s analytics
  API. The only difference is the data source: Once runs instead of
  Bazel invocations. Every row/summary/series field the render reads
  from Bazel data is present here in the same shape.
  """

  import Ecto.Query

  alias Tuist.OnceEvents.Run
  alias Tuist.Repo

  @doc """
  List Once runs with pagination + sorting + filters, shaped like
  `Tuist.Bazel.list_invocations/3` so the same LiveView render can
  consume them.
  """
  def list_invocations(project_id, flop_params \\ %{}, opts \\ []) do
    commands = Keyword.get(opts, :commands)

    base =
      Run
      |> where([r], r.project_id == ^project_id)
      |> maybe_filter_kinds(commands)
      |> maybe_filter_period(opts)
      |> maybe_filter_environment(opts)
      |> apply_flop_filters(Map.get(flop_params, :filters, []))

    order_by = Map.get(flop_params, :order_by, [:finished_at])
    order_directions = Map.get(flop_params, :order_directions, [:desc])

    page = Map.get(flop_params, :page, 1)
    page_size = Map.get(flop_params, :page_size, 20)

    total_count = Repo.aggregate(base, :count, :id)
    total_pages = max(1, ceil_div(total_count, page_size))
    current_page = max(1, min(page, total_pages))

    rows =
      base
      |> apply_flop_order(order_by, order_directions)
      |> limit(^page_size)
      |> offset(^((current_page - 1) * page_size))
      |> Repo.all()
      |> Enum.map(&to_invocation/1)

    meta = %{current_page: current_page, total_pages: total_pages, total_count: total_count}
    {rows, meta}
  end

  @doc """
  True if the project has any Once runs, optionally filtered by kind.
  """
  def invocations_present?(project_id, commands \\ nil) do
    Run
    |> where([r], r.project_id == ^project_id)
    |> maybe_filter_kinds(commands)
    |> limit(1)
    |> Repo.aggregate(:count, :id)
    |> Kernel.>(0)
  end

  @doc """
  Aggregate summary numbers over `opts` (kind + period). Shape matches
  `Tuist.Bazel.summary/2`: total, successful, failed, average and
  percentile durations. Percentiles come from Postgres
  `percentile_cont`.
  """
  def summary(project_id, opts \\ []) do
    commands = Keyword.get(opts, :commands)

    row =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> maybe_filter_kinds(commands)
      |> maybe_filter_period(opts)
      |> maybe_filter_environment(opts)
      |> select([r], %{
        total: count(r.id),
        successful:
          sum(
            fragment(
              "(case when coalesce(?, -1) = 0 then 1 else 0 end)",
              r.exit_status
            )
          ),
        failed:
          sum(
            fragment(
              "(case when coalesce(?, 0) <> 0 then 1 else 0 end)",
              r.exit_status
            )
          ),
        average_duration_ms: fragment("coalesce(avg(?), 0)", r.wall_ms),
        median_duration_ms: fragment("coalesce(percentile_cont(0.5) within group (order by ?), 0)", r.wall_ms),
        p90_duration_ms: fragment("coalesce(percentile_cont(0.9) within group (order by ?), 0)", r.wall_ms),
        p99_duration_ms: fragment("coalesce(percentile_cont(0.99) within group (order by ?), 0)", r.wall_ms)
      })
      |> Repo.one()

    normalize_summary(row || empty_summary())
  end

  @scatter_data_limit 1000

  @doc """
  One point per finalized run: its wall duration against when it started,
  grouped for the scatter chart. `:group_by` is `:host` or `:version`, the
  same dimensions `Tuist.OnceEvents.CacheAnalytics.hit_rate_scatter_data/2`
  splits on, and the shape is what `TuistWeb.Components.ScatterChart` wants.
  """
  def duration_scatter_data(project_id, opts \\ []) do
    commands = Keyword.get(opts, :commands)
    {start_dt, end_dt} = period_datetimes(opts)
    group_by = Keyword.get(opts, :group_by, :host)

    runs =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> maybe_filter_kinds(commands)
      |> maybe_filter_environment(opts)
      |> where([r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> where([r], not is_nil(r.wall_ms) and r.wall_ms > 0)
      |> order_by([r], desc: r.started_at)
      |> limit(^@scatter_data_limit)
      |> select([r], %{
        run_id: r.run_id,
        started_at: r.started_at,
        host_class: r.host_class,
        once_version: r.once_version,
        kind: r.kind,
        value: r.wall_ms
      })
      |> Repo.all()

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
                value: [DateTime.to_unix(run.started_at, :millisecond), run.value],
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

  defp scatter_group(run, :version), do: scatter_presence(run.once_version, "Unknown version")
  defp scatter_group(run, _host), do: scatter_presence(run.host_class, "Unknown host")

  defp scatter_presence(value, _fallback) when is_binary(value) and value != "", do: value
  defp scatter_presence(_value, fallback), do: fallback

  @doc """
  Time-bucketed series over the selected period. Same shape as
  `Tuist.Bazel.invocation_analytics/2`: `dates` + one `_values` list
  per widget. Bucket granularity is `:hour` if the period is short
  (<=48h), otherwise `:day`.
  """
  def invocation_analytics(project_id, opts \\ []) do
    commands = Keyword.get(opts, :commands)
    {start_dt, end_dt} = period_datetimes(opts)
    granularity = granularity_for(start_dt, end_dt)

    rows =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> maybe_filter_kinds(commands)
      |> maybe_filter_environment(opts)
      |> where([r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> group_by([r], fragment("date_trunc(?, ?)", ^to_string(granularity), r.started_at))
      |> select([r], %{
        # `min(started_at)` under the group is always the bucket
        # boundary, but reuses aggregation instead of trying to
        # reference the truncated expression twice — Ecto renumbers
        # positional `?` parameters per clause so the group_by and
        # select fragments end up as distinct expressions in the
        # generated SQL and Postgres refuses the query.
        bucket: min(r.started_at),
        total: count(r.id),
        successful:
          sum(
            fragment(
              "(case when coalesce(?, -1) = 0 then 1 else 0 end)",
              r.exit_status
            )
          ),
        failed:
          sum(
            fragment(
              "(case when coalesce(?, 0) <> 0 then 1 else 0 end)",
              r.exit_status
            )
          ),
        average_duration_ms: fragment("coalesce(avg(?), 0)", r.wall_ms),
        median_duration_ms: fragment("coalesce(percentile_cont(0.5) within group (order by ?), 0)", r.wall_ms),
        p90_duration_ms: fragment("coalesce(percentile_cont(0.9) within group (order by ?), 0)", r.wall_ms),
        p99_duration_ms: fragment("coalesce(percentile_cont(0.99) within group (order by ?), 0)", r.wall_ms)
      })
      |> Repo.all()

    by_bucket = Map.new(rows, fn row -> {truncate_bucket(row.bucket, granularity), row} end)
    dates = full_bucket_range(start_dt, end_dt, granularity)

    {total_values, success_rate_values, failed_values, average_duration_values, median_duration_values,
     p90_duration_values, p99_duration_values} =
      Enum.reduce(dates, {[], [], [], [], [], [], []}, fn date, acc ->
        row = Map.get(by_bucket, date, empty_bucket())

        {t, sr, fv, avg, p50, p90, p99} = acc

        total = to_number(row.total)
        successful = to_number(row.successful)
        failed = to_number(row.failed)
        success_rate = if total > 0, do: successful / total * 100.0, else: 0.0

        {[total | t], [success_rate | sr], [failed | fv], [to_number(row.average_duration_ms) | avg],
         [to_number(row.median_duration_ms) | p50], [to_number(row.p90_duration_ms) | p90],
         [to_number(row.p99_duration_ms) | p99]}
      end)

    %{
      dates: Enum.map(dates, &format_bucket(&1, granularity)),
      total_values: Enum.reverse(total_values),
      success_rate_values: Enum.reverse(success_rate_values),
      failed_values: Enum.reverse(failed_values),
      average_duration_values: Enum.reverse(average_duration_values),
      median_duration_values: Enum.reverse(median_duration_values),
      p90_duration_values: Enum.reverse(p90_duration_values),
      p99_duration_values: Enum.reverse(p99_duration_values)
    }
  end

  @doc """
  Configuration Insights: average build duration split by one dimension.
  Same shape as `Tuist.Bazel.build_duration_analytics_by_version/2`
  (`[%{category, value}]`), which is what the bar chart renders.

  `dimension` is `:version` (the Once release), `:host` (the host class the
  run executed on) or `:environment` (CI against a developer machine). The
  Xcode page splits the same card three ways; Once reports a single
  `host_class` where Xcode has separate device and macOS version columns,
  so environment stands in as the third axis.
  """
  def build_duration_analytics_by_version(project_id, opts \\ []) do
    build_duration_analytics_by(project_id, :version, opts)
  end

  def build_duration_analytics_by(project_id, dimension, opts \\ [])

  def build_duration_analytics_by(project_id, :environment, opts) do
    project_id
    |> duration_by_dimension_query(opts)
    |> group_by([r], r.is_ci)
    |> select([r], %{
      is_ci: r.is_ci,
      value: fragment("coalesce(avg(?), 0)", r.wall_ms)
    })
    |> order_by([r], asc: r.is_ci)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{category: environment_category(row.is_ci), value: to_number(row.value)}
    end)
  end

  def build_duration_analytics_by(project_id, dimension, opts) do
    column = insight_column(dimension)

    project_id
    |> duration_by_dimension_query(opts)
    |> where([r], not is_nil(field(r, ^column)) and field(r, ^column) != "")
    |> group_by([r], field(r, ^column))
    |> select([r], %{
      category: field(r, ^column),
      value: fragment("coalesce(avg(?), 0)", r.wall_ms)
    })
    |> order_by([r], asc: field(r, ^column))
    |> Repo.all()
    |> Enum.map(fn row -> Map.update!(row, :value, &to_number/1) end)
  end

  defp duration_by_dimension_query(project_id, opts) do
    Run
    |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
    |> maybe_filter_kinds(Keyword.get(opts, :commands))
    |> maybe_filter_period(opts)
    |> maybe_filter_environment(opts)
  end

  defp insight_column(:host), do: :host_class
  defp insight_column(_version), do: :once_version

  defp environment_category(true), do: "CI"
  defp environment_category(_local), do: "Local"

  # ---- Internals --------------------------------------------------------

  defp maybe_filter_kinds(query, nil), do: query
  defp maybe_filter_kinds(query, []), do: query

  defp maybe_filter_kinds(query, [_ | _] = commands) do
    kinds = Enum.map(commands, &normalize_command/1)
    where(query, [r], r.kind in ^kinds)
  end

  defp maybe_filter_kinds(query, single) when is_binary(single) do
    where(query, [r], r.kind == ^normalize_command(single))
  end

  defp normalize_command("build"), do: "build"
  defp normalize_command("test"), do: "test"
  defp normalize_command(other), do: to_string(other)

  defp maybe_filter_period(query, opts) do
    with %DateTime{} = start_dt <- Keyword.get(opts, :start_datetime),
         %DateTime{} = end_dt <- Keyword.get(opts, :end_datetime) do
      where(query, [r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
    else
      _ -> query
    end
  end

  # `:is_ci` is the same opt name `Tuist.Builds` takes for Xcode, so the
  # overview translates its dropdown the same way for both build systems.
  # Anything other than a boolean leaves the query unfiltered, which is what
  # the "Any" selection passes.
  defp maybe_filter_environment(query, opts) do
    case Keyword.get(opts, :is_ci) do
      is_ci when is_boolean(is_ci) -> where(query, [r], r.is_ci == ^is_ci)
      _ -> query
    end
  end

  # Only two invocation-level filters land here: `:status` (mapped to
  # exit_status) and `:command` (mapped to kind). Anything else is a
  # no-op so a stale query string never crashes the page.
  defp apply_flop_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, q ->
      case {filter.field, filter.op, filter.value} do
        {:status, :==, "success"} ->
          where(q, [r], r.finalization == "finalized" and r.exit_status == 0)

        {:status, :==, "failure"} ->
          where(q, [r], r.finalization == "finalized" and r.exit_status != 0)

        {:command, :=~, term} when is_binary(term) and term != "" ->
          pattern = "%" <> String.replace(term, ~r/[\\%_]/, fn c -> "\\" <> c end) <> "%"
          where(q, [r], ilike(r.command_display, ^pattern) or ilike(r.kind, ^pattern))

        _ ->
          q
      end
    end)
  end

  defp apply_flop_order(query, order_by, order_directions) do
    order_by
    |> Enum.zip(order_directions)
    |> Enum.reduce(query, fn {field, direction}, q ->
      column = map_order_field(field)

      case direction do
        :asc -> order_by(q, [r], asc_nulls_last: field(r, ^column))
        _ -> order_by(q, [r], desc_nulls_last: field(r, ^column))
      end
    end)
  end

  defp map_order_field(:command), do: :command_display
  defp map_order_field(:status), do: :exit_status
  defp map_order_field(:duration_ms), do: :wall_ms
  defp map_order_field(:finished_at), do: :finalized_at
  defp map_order_field(other), do: other

  # Cast a Run row into the shape `BazelInvocationsLive` expects:
  # invocation_id, command (kind), status, duration_ms, finished_at,
  # cache (nested with hit_rate/download/upload), plus a couple of
  # display helpers.
  defp to_invocation(%Run{} = run) do
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
      status: run_status(run),
      duration_ms: run.wall_ms || 0,
      finished_at: run.finalized_at || run.started_at,
      is_ci: run.is_ci || false,
      git_rev: run.git_rev,
      git_branch: run.git_branch,
      host_class: run.host_class,
      cache: %{
        hit_rate: hit_rate,
        download_bytes: run.cache_bytes_downloaded || 0,
        upload_bytes: run.cache_bytes_uploaded || 0
      }
    }
  end

  # Only a finalized run has a verdict. Reporting everything else as a
  # failure meant a build was listed as failed while it was still running,
  # and counted as one in the failure roll-ups. `lost` is terminal: the
  # client stopped reporting and the run will never finalize.
  defp run_status(%{finalization: "finalized", exit_status: 0}), do: "success"
  defp run_status(%{finalization: "finalized"}), do: "failure"
  defp run_status(%{finalization: "lost"}), do: "failure"
  defp run_status(_run), do: "in_progress"

  defp display_command(run) do
    cond do
      is_binary(run.command_display) and run.command_display != "" -> run.command_display
      is_binary(run.kind) and run.kind != "" -> "once " <> run.kind
      true -> "once"
    end
  end

  defp ceil_div(a, b) when b > 0, do: div(a + b - 1, b)
  defp ceil_div(_, _), do: 1

  defp period_datetimes(opts) do
    case {Keyword.get(opts, :start_datetime), Keyword.get(opts, :end_datetime)} do
      {%DateTime{} = s, %DateTime{} = e} ->
        {s, e}

      _ ->
        end_dt = DateTime.utc_now()
        start_dt = DateTime.add(end_dt, -30 * 86_400, :second)
        {start_dt, end_dt}
    end
  end

  defp granularity_for(start_dt, end_dt) do
    diff_hours = DateTime.diff(end_dt, start_dt, :second) / 3600
    if diff_hours <= 48, do: :hour, else: :day
  end

  defp truncate_bucket(%DateTime{} = dt, :day), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp truncate_bucket(%DateTime{} = dt, :hour),
    do: DateTime.to_iso8601(%{dt | minute: 0, second: 0, microsecond: {0, 0}})

  defp truncate_bucket(%NaiveDateTime{} = ndt, granularity) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> truncate_bucket(granularity)
  end

  defp full_bucket_range(start_dt, end_dt, :day) do
    start_date = DateTime.to_date(start_dt)
    end_date = DateTime.to_date(end_dt)
    start_date |> Date.range(end_date) |> Enum.map(&Date.to_iso8601/1)
  end

  defp full_bucket_range(start_dt, end_dt, :hour) do
    start_dt = %{start_dt | minute: 0, second: 0, microsecond: {0, 0}}
    end_dt = %{end_dt | minute: 0, second: 0, microsecond: {0, 0}}
    diff_hours = end_dt |> DateTime.diff(start_dt, :second) |> div(3600)

    Enum.map(0..diff_hours, fn h ->
      start_dt |> DateTime.add(h * 3600, :second) |> DateTime.to_iso8601()
    end)
  end

  defp format_bucket(iso, _granularity), do: iso

  defp to_number(nil), do: 0
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n
  defp to_number(_), do: 0

  defp normalize_summary(row) do
    %{
      total: to_number(row.total),
      successful: to_number(row.successful),
      failed: to_number(row.failed),
      average_duration_ms: to_number(row.average_duration_ms),
      median_duration_ms: to_number(row.median_duration_ms),
      p90_duration_ms: to_number(row.p90_duration_ms),
      p99_duration_ms: to_number(row.p99_duration_ms)
    }
  end

  defp empty_summary do
    %{
      total: 0,
      successful: 0,
      failed: 0,
      average_duration_ms: 0,
      median_duration_ms: 0,
      p90_duration_ms: 0,
      p99_duration_ms: 0
    }
  end

  defp empty_bucket do
    %{
      total: 0,
      successful: 0,
      failed: 0,
      average_duration_ms: 0,
      median_duration_ms: 0,
      p90_duration_ms: 0,
      p99_duration_ms: 0
    }
  end
end
