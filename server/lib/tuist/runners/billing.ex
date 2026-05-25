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

  @doc """
  Total billable milliseconds for `account_id` over
  `[period_start, period_end]`. Each Pod session contributes only
  the portion of its runtime that lies inside the window.
  """
  def compute_milliseconds(account_id, %DateTime{} = period_start, %DateTime{} = period_end)
      when is_integer(account_id) do
    now = DateTime.utc_now()

    sessions =
      account_id
      |> sessions_overlapping(period_start, period_end)
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
  def compute_milliseconds_per_day(account_id, %DateTime{} = period_start, %DateTime{} = period_end)
      when is_integer(account_id) do
    now = DateTime.utc_now()

    sessions =
      account_id
      |> sessions_overlapping(period_start, period_end)
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
end
