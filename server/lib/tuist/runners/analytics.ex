defmodule Tuist.Runners.Analytics do
  @moduledoc """
  Account-scoped analytics over the `runner_jobs` ClickHouse table.

  Two kinds of aggregation:

    * **Job-level** — one data point per `workflow_job_id`. Drives the
      "Total jobs", "Avg. job duration", and "Cumulative compute
      minutes" widgets.
    * **Workflow-level** — collapses jobs in the same workflow_run
      into one duration data point (`max(completed_at) - min(started_at)`).
      Drives the "Avg. workflow duration" widget.

  Each function returns a map with the value + a per-bucket time
  series (`%{dates: […], values: […]}`) so the LiveView can drop it
  straight into a chart.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Runners.Job

  @default_window_days 30

  @doc """
  Total job count over the window plus a daily series and the
  trend (% change) versus the equivalent prior window.

  Returns `%{count, trend, dates, values}`.
  """
  def jobs_count(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    count = jobs_count_in_range(account_id, start_dt, end_dt)
    previous_count = jobs_count_in_range(account_id, prev_start_dt, prev_end_dt)

    rows = jobs_count_per_day(account_id, start_dt, end_dt)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp jobs_count_in_range(account_id, start_dt, end_dt) do
    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
      |> select([j], %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count
  end

  @doc """
  Total count of failed jobs over the window + daily series + trend.
  A "failed" job is one that reached `status='completed'` with a
  `conclusion='failure'`. Cancelled/skipped don't count — the
  customer cares about runner-attributable failures, not the
  build-author's choices.
  """
  def failed_jobs_count(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    count = failed_count_in_range(account_id, start_dt, end_dt)
    previous_count = failed_count_in_range(account_id, prev_start_dt, prev_end_dt)
    rows = failed_jobs_per_day(account_id, start_dt, end_dt)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp failed_count_in_range(account_id, start_dt, end_dt) do
    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where(
        [j],
        j.account_id == ^account_id and j.enqueued_at >= ^start_dt and
          j.enqueued_at <= ^end_dt and j.status == "completed" and
          j.conclusion == "failure"
      )
      |> select([j], %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count
  end

  defp failed_jobs_per_day(account_id, start_dt, end_dt) do
    Job
    |> from(hints: ["FINAL"])
    |> where(
      [j],
      j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt and
        j.status == "completed" and j.conclusion == "failure"
    )
    |> group_by([j], fragment("toDate(?)", j.completed_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.completed_at),
      value: count(j.workflow_job_id)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.completed_at))
    |> ClickHouseRepo.all()
  end

  defp jobs_count_per_day(account_id, start_dt, end_dt) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
    |> group_by([j], fragment("toDate(?)", j.enqueued_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.enqueued_at),
      value: count(j.workflow_job_id)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.enqueued_at))
    |> ClickHouseRepo.all()
  end

  @doc """
  Sum of completed-job runtime (`completed_at - started_at`) in
  milliseconds over the window, plus a daily series and a trend.
  """
  def cumulative_minutes(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    total_ms = total_completed_ms(account_id, start_dt, end_dt)
    previous_total_ms = total_completed_ms(account_id, prev_start_dt, prev_end_dt)

    rows =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> group_by([j], fragment("toDate(?)", j.completed_at))
      |> select([j], %{
        date: fragment("toDate(?)", j.completed_at),
        value:
          fragment(
            "sum(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          )
      })
      |> order_by([j], asc: fragment("toDate(?)", j.completed_at))
      |> ClickHouseRepo.all()

    minute_rows =
      Enum.map(rows, fn row ->
        %{date: row.date, value: row.value |> div(60_000) |> trunc()}
      end)

    filled = fill_dates(minute_rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      total_ms: total_ms || 0,
      trend: trend(previous_total_ms, total_ms),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp total_completed_ms(account_id, start_dt, end_dt) do
    [%{total_ms: total_ms} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> select([j], %{
        total_ms:
          fragment(
            "sum(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          )
      })
      |> ClickHouseRepo.all()
      |> default_empty(%{total_ms: 0})

    total_ms || 0
  end

  @doc """
  Per-completed-job duration aggregates over the window: avg, p50,
  p90, p99, plus daily series for each percentile so the chart can
  switch with the percentile dropdown.
  """
  def jobs_duration(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    current = jobs_duration_aggregates(account_id, start_dt, end_dt)
    previous = jobs_duration_aggregates(account_id, prev_start_dt, prev_end_dt)
    rows = duration_buckets_per_day(account_id, start_dt, end_dt, &job_duration_select/1)
    filled = fill_duration_dates(rows, start_dt, end_dt)

    %{
      avg: trunc_or_zero(current.avg),
      p50: trunc_or_zero(current.p50),
      p90: trunc_or_zero(current.p90),
      p99: trunc_or_zero(current.p99),
      trend_avg: trend(trunc_or_zero(previous.avg), trunc_or_zero(current.avg)),
      trend_p50: trend(trunc_or_zero(previous.p50), trunc_or_zero(current.p50)),
      trend_p90: trend(trunc_or_zero(previous.p90), trunc_or_zero(current.p90)),
      trend_p99: trend(trunc_or_zero(previous.p99), trunc_or_zero(current.p99)),
      dates: Enum.map(filled, & &1.date),
      avg_values: Enum.map(filled, & &1.avg),
      p50_values: Enum.map(filled, & &1.p50),
      p90_values: Enum.map(filled, & &1.p90),
      p99_values: Enum.map(filled, & &1.p99)
    }
  end

  defp jobs_duration_aggregates(account_id, start_dt, end_dt) do
    [aggregates | _] =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> select([j], %{
        avg:
          fragment(
            "avg(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          ),
        p50:
          fragment(
            "quantile(0.5)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          ),
        p90:
          fragment(
            "quantile(0.9)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          ),
        p99:
          fragment(
            "quantile(0.99)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.completed_at,
            j.started_at
          )
      })
      |> ClickHouseRepo.all()
      |> default_empty(%{avg: 0, p50: 0, p90: 0, p99: 0})

    aggregates
  end

  @doc """
  Per-workflow_run duration aggregates. A workflow's duration is
  `max(completed_at) - min(started_at)` across the jobs that share a
  `workflow_run_id` — i.e. how long the whole CI run took from first
  start to last finish.
  """
  def workflows_duration(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    current = workflows_duration_aggregates(account_id, start_dt, end_dt)
    previous = workflows_duration_aggregates(account_id, prev_start_dt, prev_end_dt)
    rows = workflows_duration_per_day(account_id, start_dt, end_dt)
    filled = fill_duration_dates(rows, start_dt, end_dt)

    %{
      avg: trunc_or_zero(current.avg),
      p50: trunc_or_zero(current.p50),
      p90: trunc_or_zero(current.p90),
      p99: trunc_or_zero(current.p99),
      trend_avg: trend(trunc_or_zero(previous.avg), trunc_or_zero(current.avg)),
      trend_p50: trend(trunc_or_zero(previous.p50), trunc_or_zero(current.p50)),
      trend_p90: trend(trunc_or_zero(previous.p90), trunc_or_zero(current.p90)),
      trend_p99: trend(trunc_or_zero(previous.p99), trunc_or_zero(current.p99)),
      dates: Enum.map(filled, & &1.date),
      avg_values: Enum.map(filled, & &1.avg),
      p50_values: Enum.map(filled, & &1.p50),
      p90_values: Enum.map(filled, & &1.p90),
      p99_values: Enum.map(filled, & &1.p99)
    }
  end

  defp workflows_duration_aggregates(account_id, start_dt, end_dt) do
    runs_subquery = workflow_runs_subquery(account_id, start_dt, end_dt)

    [aggregates | _] =
      from(r in subquery(runs_subquery),
        select: %{
          avg: fragment("avg(?)", r.run_ms),
          p50: fragment("quantile(0.5)(?)", r.run_ms),
          p90: fragment("quantile(0.9)(?)", r.run_ms),
          p99: fragment("quantile(0.99)(?)", r.run_ms)
        }
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{avg: 0, p50: 0, p90: 0, p99: 0})

    aggregates
  end

  defp workflows_duration_per_day(account_id, start_dt, end_dt) do
    runs_subquery = workflow_runs_subquery(account_id, start_dt, end_dt)

    from(r in subquery(runs_subquery),
      group_by: r.completion_date,
      order_by: r.completion_date,
      select: %{
        date: r.completion_date,
        avg: fragment("avg(?)", r.run_ms),
        p50: fragment("quantile(0.5)(?)", r.run_ms),
        p90: fragment("quantile(0.9)(?)", r.run_ms),
        p99: fragment("quantile(0.99)(?)", r.run_ms)
      }
    )
    |> ClickHouseRepo.all()
  end

  defp workflow_runs_subquery(account_id, start_dt, end_dt) do
    Job
    |> from(hints: ["FINAL"])
    |> completed_in_window(account_id, start_dt, end_dt)
    |> where([j], j.workflow_run_id > 0)
    |> group_by([j], [j.workflow_run_id])
    |> select([j], %{
      completion_date: fragment("toDate(max(?))", j.completed_at),
      run_ms:
        fragment(
          "toUnixTimestamp64Milli(max(?)) - toUnixTimestamp64Milli(min(?))",
          j.completed_at,
          j.started_at
        )
    })
  end

  # Percentage change from previous to current. Returns 0.0 when
  # either side is zero so the badge stays neutral on cold accounts.
  defp trend(previous, current) when is_number(previous) and is_number(current) do
    cond do
      previous == 0 -> 0.0
      current == 0 -> 0.0
      true -> Float.round(current / previous * 100, 1) - 100.0
    end
  end

  defp trend(_, _), do: 0.0

  defp duration_buckets_per_day(account_id, start_dt, end_dt, _select_fn) do
    Job
    |> from(hints: ["FINAL"])
    |> completed_in_window(account_id, start_dt, end_dt)
    |> group_by([j], fragment("toDate(?)", j.completed_at))
    |> order_by([j], asc: fragment("toDate(?)", j.completed_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.completed_at),
      avg:
        fragment(
          "avg(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.completed_at,
          j.started_at
        ),
      p50:
        fragment(
          "quantile(0.5)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.completed_at,
          j.started_at
        ),
      p90:
        fragment(
          "quantile(0.9)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.completed_at,
          j.started_at
        ),
      p99:
        fragment(
          "quantile(0.99)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.completed_at,
          j.started_at
        )
    })
    |> ClickHouseRepo.all()
  end

  defp completed_in_window(query, account_id, start_dt, end_dt) do
    where(
      query,
      [j],
      j.account_id == ^account_id and j.status == "completed" and
        j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt and
        fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
        fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at)
    )
  end

  defp window(opts) do
    end_dt = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    start_dt =
      Keyword.get(opts, :start_datetime, DateTime.add(end_dt, -@default_window_days, :day))

    {start_dt, end_dt}
  end

  # Mirror window for trend comparison: same length, immediately
  # preceding the current period.
  defp previous_window(start_dt, end_dt) do
    delta_seconds = DateTime.diff(end_dt, start_dt, :second)
    {DateTime.add(start_dt, -delta_seconds, :second), start_dt}
  end

  defp default_empty([], default), do: [default]
  defp default_empty(rows, _default), do: rows

  # Fills the date range with zero-valued rows where the ClickHouse
  # grouped query didn't produce a bucket. Without this the line
  # chart skips over empty days and renders as a single connected
  # blip, which looks broken on small datasets.
  defp fill_dates(rows, start_dt, end_dt, value_fn) do
    by_date = Map.new(rows, &{&1.date, value_fn.(&1)})

    daily_range(start_dt, end_dt)
    |> Enum.map(fn date ->
      %{date: date, value: Map.get(by_date, date, 0)}
    end)
  end

  defp fill_duration_dates(rows, start_dt, end_dt) do
    by_date =
      Map.new(rows, fn row ->
        {row.date,
         %{
           avg: trunc_or_zero(row.avg),
           p50: trunc_or_zero(row.p50),
           p90: trunc_or_zero(row.p90),
           p99: trunc_or_zero(row.p99)
         }}
      end)

    empty = %{avg: 0, p50: 0, p90: 0, p99: 0}

    daily_range(start_dt, end_dt)
    |> Enum.map(fn date ->
      values = Map.get(by_date, date, empty)
      Map.put(values, :date, date)
    end)
  end

  defp daily_range(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    Date.range(DateTime.to_date(start_dt), DateTime.to_date(end_dt))
  end

  defp trunc_or_zero(nil), do: 0
  defp trunc_or_zero(value) when is_number(value), do: trunc(value)

  # Silence "unused alias" warnings; the select_fn parameter is kept
  # for future extensibility but `duration_buckets_per_day/4` ignores it.
  defp job_duration_select(_), do: :ok
end
