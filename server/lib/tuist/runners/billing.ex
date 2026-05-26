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
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.RunnerSession

  @default_window_days 30

  # Safety clamp for sessions whose `stopped` event was never
  # delivered (controller crash + Pod garbage-collected from K8s
  # before recovery). Without this, an indefinitely-open session
  # bills against `LEAST(now(), period_end)` for as long as it
  # stays open, which is exactly the over-bill the
  # controller-reported-close architecture exists to prevent. 6
  # hours matches the default `workflow_job` hard timeout on
  # GitHub-hosted runners, so the clamp never trims a legitimate
  # session — it only bounds the worst case after the
  # authoritative signal got lost.
  @max_session_lifetime_seconds 6 * 60 * 60

  @doc """
  Total billable minutes for `account_id` over the window, plus a
  per-bucket series + trend versus the previous equivalent window.
  The underlying source is `runner_sessions` — the same number that
  invoicing will charge against.

  Options:

    * `:start_datetime` / `:end_datetime` — window. Defaults to
      the last 30 days.
    * `:repo`, `:workflow_name` — exact-match scope filters.
    * `:platform` — `"macos"` or `"linux"`, narrows on the
      `fleet_name` prefix.

  Returns `%{total_ms, trend, dates, values}` where `values` are
  whole minutes per bucket (truncated for display; precision is
  preserved in `total_ms`).
  """
  def compute_minutes(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)
    bucket = bucket_opt(opts, start_dt, end_dt)

    total_ms = compute_milliseconds(account_id, start_dt, end_dt, opts)
    previous_total_ms = compute_milliseconds(account_id, prev_start_dt, prev_end_dt, opts)

    per_bucket = compute_milliseconds_per_bucket(account_id, start_dt, end_dt, bucket, opts)

    filled =
      start_dt
      |> bucket_range(end_dt, bucket)
      |> Enum.map(fn date ->
        ms = Map.get(per_bucket, date, 0)
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
  `:platform`) as `compute_minutes/2` so a filtered query and a
  filtered invoice line up against the same shape.
  """
  def compute_milliseconds(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    now = DateTime.utc_now()

    query =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> scope(opts)
      |> select([s], %{
        total_ms:
          fragment(
            """
            COALESCE(SUM(GREATEST(
              0,
              (EXTRACT(EPOCH FROM (
                LEAST(
                  COALESCE(?, ?),
                  ?,
                  ? + make_interval(secs => ?)
                ) - GREATEST(?, ?)
              )) * 1000)::bigint
            )), 0)::bigint
            """,
            s.ended_at,
            ^now,
            ^period_end,
            s.started_at,
            ^@max_session_lifetime_seconds,
            s.started_at,
            ^period_start
          )
      })

    case Repo.one(query) do
      %{total_ms: ms} when is_integer(ms) -> ms
      _ -> 0
    end
  end

  @doc """
  Returns a bucket-keyed map of billable milliseconds within the
  window. Sessions crossing a bucket boundary contribute to each
  bucket they overlap. `bucket` is `:hour` (`%{DateTime.t() =>
  integer_ms}`) or `:day` (`%{Date.t() => integer_ms}`).

  Used to drive the per-bucket series chart on the billing/jobs
  pages. The caller can format the values however they want
  (minutes, hours, dollars) at render time.
  """
  def compute_milliseconds_per_bucket(
        account_id,
        %DateTime{} = period_start,
        %DateTime{} = period_end,
        bucket,
        opts \\ []
      )
      when is_integer(account_id) and bucket in [:hour, :day] do
    now = DateTime.utc_now()

    # SQL pipeline:
    #   1. `overlapping` — sessions for this account whose window
    #      touches [period_start, period_end] (CTE).
    #   2. `buckets` — explode each session into one row per bucket
    #      (UTC day, or hour) it overlaps using `generate_series`.
    #   3. Outer SELECT — per-bucket SUM of the intersection between
    #      (session, bucket, billing-period). All math in Postgres,
    #      so a busy window doesn't materialise thousands of rows
    #      into the BEAM.
    overlapping =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> scope(opts)
      |> select([s], %{
        started_at: s.started_at,
        # Clamp the upper bound at `started_at + max_lifetime` so a
        # session whose `stopped` event was never delivered can't
        # bill past the safety cap. Mirrors the same clamp in
        # `compute_milliseconds/4`.
        effective_end:
          fragment(
            "LEAST(COALESCE(?, ?), ? + make_interval(secs => ?))",
            s.ended_at,
            ^now,
            s.started_at,
            ^@max_session_lifetime_seconds
          )
      })

    buckets = buckets_query(overlapping, period_start, period_end, bucket)

    from(b in subquery(buckets),
      group_by: b.day,
      order_by: b.day,
      select: {b.day, fragment("SUM(?)::bigint", b.intersection_ms)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp buckets_query(overlapping, period_start, period_end, :day) do
    from(o in subquery(overlapping),
      inner_lateral_join:
        bucket in fragment(
          """
          (SELECT generate_series(
            GREATEST(?, ?::timestamptz)::date,
            LEAST(?, ?::timestamptz)::date,
            '1 day'::interval
          )::date AS day)
          """,
          o.started_at,
          ^period_start,
          o.effective_end,
          ^period_end
        ),
      on: true,
      select: %{
        day: bucket.day,
        intersection_ms:
          fragment(
            """
            GREATEST(0, (EXTRACT(EPOCH FROM (
              LEAST(?, (?::date + INTERVAL '1 day')::timestamptz, ?) -
              GREATEST(?, ?::timestamptz, ?)
            )) * 1000)::bigint)
            """,
            o.effective_end,
            bucket.day,
            ^period_end,
            o.started_at,
            bucket.day,
            ^period_start
          )
      }
    )
  end

  defp buckets_query(overlapping, period_start, period_end, :hour) do
    from(o in subquery(overlapping),
      inner_lateral_join:
        bucket in fragment(
          """
          (SELECT generate_series(
            date_trunc('hour', GREATEST(?, ?::timestamptz)),
            date_trunc('hour', LEAST(?, ?::timestamptz)),
            '1 hour'::interval
          ) AS day)
          """,
          o.started_at,
          ^period_start,
          o.effective_end,
          ^period_end
        ),
      on: true,
      select: %{
        day: bucket.day,
        intersection_ms:
          fragment(
            """
            GREATEST(0, (EXTRACT(EPOCH FROM (
              LEAST(?, ? + INTERVAL '1 hour', ?) -
              GREATEST(?, ?, ?)
            )) * 1000)::bigint)
            """,
            o.effective_end,
            bucket.day,
            ^period_end,
            o.started_at,
            bucket.day,
            ^period_start
          )
      }
    )
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

  defp scope(query, opts) do
    query
    |> maybe_eq(:repo, Keyword.get(opts, :repo))
    |> maybe_eq(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_platform(Keyword.get(opts, :platform))
  end

  defp maybe_eq(query, _field, nil), do: query
  defp maybe_eq(query, _field, ""), do: query
  defp maybe_eq(query, _field, "any"), do: query

  defp maybe_eq(query, :repo, value) when is_binary(value), do: where(query, [s], s.repo == ^value)

  defp maybe_eq(query, :workflow_name, value) when is_binary(value), do: where(query, [s], s.workflow_name == ^value)

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

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :day) do
    Date.range(DateTime.to_date(start_dt), DateTime.to_date(end_dt))
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :hour) do
    # Microsecond precision matches Postgres `date_trunc('hour', …)`
    # output (`{0, 6}`) so the DateTime keys are structurally equal
    # when used as map lookups against `compute_milliseconds_per_bucket`.
    floor_start = %{start_dt | minute: 0, second: 0, microsecond: {0, 6}}
    floor_end = %{end_dt | minute: 0, second: 0, microsecond: {0, 6}}

    floor_start
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, floor_end) != :gt))
  end

  defp bucket_opt(opts, start_dt, end_dt) do
    case Keyword.get(opts, :bucket) do
      bucket when bucket in [:hour, :day] -> bucket
      _ -> Analytics.bucket_for_window(start_dt, end_dt)
    end
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
