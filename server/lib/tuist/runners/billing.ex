defmodule Tuist.Runners.Billing do
  @moduledoc """
  Billing-grade compute-time aggregation over `runner_sessions`.

  Each row in `runner_sessions` is a Pod lifecycle — `started_at`
  on claim-win, `ended_at` on completion webhook (or `NULL` for
  Pods still in flight). Invoicing reads from here, never from
  `runner_jobs`. See the migration's @moduledoc for the
  architectural rationale.

  ## Window semantics

  `compute_milliseconds/3` returns the sum of *interval
  intersections* between each session's `[started_at, ended_at]`
  and the billing window `[period_start, period_end]`:

      max(0, min(ended_at, period_end) - max(started_at, period_start))

  That treats cross-boundary sessions correctly — a Pod that ran
  for two hours across a month boundary contributes only the
  minutes that fall on each side. It's also retry-safe: each
  re-claim creates a new session row, so a workflow_job that was
  released and re-served bills for both Pods.

  ## Open sessions

  Sessions with `ended_at IS NULL` are still in flight. Their
  upper bound clamps to either `period_end` (so the billing
  query gives a snapshot of "compute consumed so far") or to
  `now()` whenever the caller queries with `period_end` set to
  the future. An orphaned Pod (controller never tore it down,
  no completion webhook) keeps billing up to whichever cap
  applies — operationally the orphan-runners worker should
  close those sessions out before they run away.

  ## Precision

  The math is in milliseconds end-to-end; rendering to minutes
  or hours happens at the formatting boundary. Daily series use
  the same interval-intersection but bucketed per UTC day, so a
  session that spans midnight contributes to both days.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession

  @default_window_days 30

  @doc """
  Customer-facing "Compute Minutes" widget shape. Drives the
  Jobs-page widget that used to read from
  `Tuist.Runners.Analytics.cumulative_minutes/2`. Returns the
  same map shape (so the LiveView swap is a one-line change),
  but the underlying source is `runner_sessions` rather than
  `runner_jobs` — i.e. the same number that invoicing will
  charge against.

  Options:

    * `:start_datetime` / `:end_datetime` — window. Defaults to
      the last 30 days.
    * `:repo`, `:workflow_name` — exact-match scope (Jobs page
      filters).
    * `:platform` — `"macos"` or `"linux"`, narrows on the
      `fleet_name` prefix the same way the rest of the runners
      pages do.

  Returns `%{total_ms, trend, dates, values}` where `values` are
  whole minutes per UTC day (truncated for display; precision is
  preserved in `total_ms`).
  """
  def compute_minutes(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    total_ms = compute_milliseconds(account_id, start_dt, end_dt, opts)
    previous_total_ms = compute_milliseconds(account_id, prev_start_dt, prev_end_dt, opts)

    per_day = compute_milliseconds_per_day(account_id, start_dt, end_dt, opts)

    filled =
      start_dt
      |> daily_range(end_dt)
      |> Enum.map(fn date ->
        ms = Map.get(per_day, date, 0)
        %{date: date, value: ms |> div(60_000) |> trunc()}
      end)

    %{
      total_ms: total_ms,
      trend: trend(previous_total_ms, total_ms),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  @doc """
  Total billable milliseconds for `account_id` over
  `[period_start, period_end]`. Each Pod session contributes only
  the portion of its runtime that lies inside the window.

  Accepts the same scope opts (`:repo`, `:workflow_name`,
  `:platform`) as `compute_minutes/2` so a filtered widget and a
  filtered invoice line up against the same query shape.
  """
  def compute_milliseconds(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    now = DateTime.utc_now()

    sessions =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> scope(opts)
      |> Repo.all()

    Enum.reduce(sessions, 0, fn session, acc ->
      acc + session_intersection_ms(session, period_start, period_end, now)
    end)
  end

  @doc """
  Returns a date-keyed map `%{Date.t() => integer_ms}` of
  billable milliseconds per UTC day within the window. Sessions
  spanning midnight contribute to each day they overlap.

  Used to drive a daily-series chart on the billing page. The
  caller can format the values however they want (minutes,
  hours, dollars) at render time.
  """
  def compute_milliseconds_per_day(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    now = DateTime.utc_now()

    sessions =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> scope(opts)
      |> Repo.all()

    Enum.reduce(sessions, %{}, fn session, acc ->
      effective_end = session.ended_at || min_dt(now, period_end)
      effective_start = session.started_at

      effective_start
      |> day_buckets(effective_end)
      |> Enum.reduce(acc, fn day, inner_acc ->
        day_start = day_to_dt(day, :start)
        day_end = day_to_dt(day, :end)

        bucket_ms =
          interval_intersection_ms(
            max_dt(effective_start, max_dt(day_start, period_start)),
            min_dt(effective_end, min_dt(day_end, period_end))
          )

        Map.update(inner_acc, day, bucket_ms, &(&1 + bucket_ms))
      end)
    end)
  end

  defp sessions_overlapping(account_id, period_start, period_end) do
    # A session overlaps the window when:
    #   started_at <= period_end AND (ended_at IS NULL OR ended_at >= period_start)
    # i.e. the session started before the window ended AND it
    # didn't already end before the window began.
    from(s in RunnerSession,
      where: s.account_id == ^account_id,
      where: s.started_at <= ^period_end,
      where: is_nil(s.ended_at) or s.ended_at >= ^period_start
    )
  end

  defp session_intersection_ms(session, period_start, period_end, now) do
    effective_end = session.ended_at || min_dt(now, period_end)
    interval_intersection_ms(max_dt(session.started_at, period_start), min_dt(effective_end, period_end))
  end

  defp interval_intersection_ms(%DateTime{} = lo, %DateTime{} = hi) do
    case DateTime.diff(hi, lo, :millisecond) do
      ms when ms > 0 -> ms
      _ -> 0
    end
  end

  defp max_dt(%DateTime{} = a, %DateTime{} = b),
    do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  defp min_dt(%DateTime{} = a, %DateTime{} = b),
    do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  defp day_buckets(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    start_date = DateTime.to_date(start_dt)
    end_date = DateTime.to_date(end_dt)

    Date.range(start_date, end_date)
  end

  defp day_to_dt(%Date{} = date, :start) do
    {:ok, dt} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    dt
  end

  defp day_to_dt(%Date{} = date, :end) do
    {:ok, dt} = DateTime.new(date, ~T[23:59:59.999999], "Etc/UTC")
    dt
  end

  defp scope(query, opts) do
    query
    |> maybe_eq(:repo, Keyword.get(opts, :repo))
    |> maybe_eq(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_platform(Keyword.get(opts, :platform))
  end

  defp maybe_eq(query, _field, nil), do: query
  defp maybe_eq(query, _field, ""), do: query
  defp maybe_eq(query, _field, "any"), do: query

  defp maybe_eq(query, :repo, value) when is_binary(value),
    do: where(query, [s], s.repo == ^value)

  defp maybe_eq(query, :workflow_name, value) when is_binary(value),
    do: where(query, [s], s.workflow_name == ^value)

  defp maybe_platform(query, nil), do: query
  defp maybe_platform(query, ""), do: query
  defp maybe_platform(query, "any"), do: query

  defp maybe_platform(query, platform) when platform in ["macos", "linux"] do
    prefix = platform <> "-"
    where(query, [s], fragment("starts_with(?, ?)", s.fleet_name, ^prefix))
  end

  defp maybe_platform(query, _), do: query

  defp window(opts) do
    end_dt = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    start_dt =
      Keyword.get(opts, :start_datetime, DateTime.add(end_dt, -@default_window_days, :day))

    {start_dt, end_dt}
  end

  defp previous_window(start_dt, end_dt) do
    delta_seconds = DateTime.diff(end_dt, start_dt, :second)
    {DateTime.add(start_dt, -delta_seconds, :second), start_dt}
  end

  defp daily_range(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    Date.range(DateTime.to_date(start_dt), DateTime.to_date(end_dt))
  end

  defp trend(previous, current) when is_number(previous) and is_number(current) do
    cond do
      previous == 0 -> 0.0
      current == 0 -> 0.0
      true -> Float.round(current / previous * 100, 1) - 100.0
    end
  end

  defp trend(_, _), do: 0.0
end
