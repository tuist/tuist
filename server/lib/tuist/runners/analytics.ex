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

    count = jobs_count_in_range(account_id, start_dt, end_dt, opts)
    previous_count = jobs_count_in_range(account_id, prev_start_dt, prev_end_dt, opts)

    rows = jobs_count_per_day(account_id, start_dt, end_dt, opts)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp jobs_count_in_range(account_id, start_dt, end_dt, opts) do
    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
      |> scope_workflow(opts)
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

    count = failed_count_in_range(account_id, start_dt, end_dt, opts)
    previous_count = failed_count_in_range(account_id, prev_start_dt, prev_end_dt, opts)
    rows = failed_jobs_per_day(account_id, start_dt, end_dt, opts)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp failed_count_in_range(account_id, start_dt, end_dt, opts) do
    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where(
        [j],
        j.account_id == ^account_id and j.enqueued_at >= ^start_dt and
          j.enqueued_at <= ^end_dt and j.status == "completed" and
          j.conclusion == "failure"
      )
      |> scope_workflow(opts)
      |> select([j], %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count
  end

  defp failed_jobs_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where(
      [j],
      j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt and
        j.status == "completed" and j.conclusion == "failure"
    )
    |> scope_workflow(opts)
    |> group_by([j], fragment("toDate(?)", j.completed_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.completed_at),
      value: count(j.workflow_job_id)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.completed_at))
    |> ClickHouseRepo.all()
  end

  defp jobs_count_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
    |> scope_workflow(opts)
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

    total_ms = total_completed_ms(account_id, start_dt, end_dt, opts)
    previous_total_ms = total_completed_ms(account_id, prev_start_dt, prev_end_dt, opts)

    rows =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
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

  defp total_completed_ms(account_id, start_dt, end_dt, opts) do
    [%{total_ms: total_ms} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
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

    current = jobs_duration_aggregates(account_id, start_dt, end_dt, opts)
    previous = jobs_duration_aggregates(account_id, prev_start_dt, prev_end_dt, opts)
    rows = duration_buckets_per_day(account_id, start_dt, end_dt, opts)
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

  defp jobs_duration_aggregates(account_id, start_dt, end_dt, opts) do
    [aggregates | _] =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
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
  Combined Total / Successful / Failed job counts over the window,
  one query per line so the Jobs page can render the breakdown as
  three series on a single chart without three round trips. Each
  line carries its own trend so the widget can label the dominant
  one.
  """
  def jobs_breakdown(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    current = breakdown_totals(account_id, start_dt, end_dt, opts)
    previous = breakdown_totals(account_id, prev_start_dt, prev_end_dt, opts)
    rows = breakdown_per_day(account_id, start_dt, end_dt, opts)
    filled = fill_breakdown_dates(rows, start_dt, end_dt)

    %{
      total: current.total,
      successful: current.successful,
      failed: current.failed,
      trend_total: trend(previous.total, current.total),
      trend_successful: trend(previous.successful, current.successful),
      trend_failed: trend(previous.failed, current.failed),
      dates: Enum.map(filled, & &1.date),
      total_values: Enum.map(filled, & &1.total),
      successful_values: Enum.map(filled, & &1.successful),
      failed_values: Enum.map(filled, & &1.failed)
    }
  end

  defp breakdown_totals(account_id, start_dt, end_dt, opts) do
    [aggregates | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
      |> scope_workflow(opts)
      |> select([j], %{
        total: count(j.workflow_job_id),
        successful: fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
        failed: fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion)
      })
      |> ClickHouseRepo.all()
      |> default_empty(%{total: 0, successful: 0, failed: 0})

    aggregates
  end

  defp breakdown_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
    |> scope_workflow(opts)
    |> group_by([j], fragment("toDate(?)", j.enqueued_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.enqueued_at),
      total: count(j.workflow_job_id),
      successful: fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
      failed: fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.enqueued_at))
    |> ClickHouseRepo.all()
  end

  defp fill_breakdown_dates(rows, start_dt, end_dt) do
    by_date =
      Map.new(rows, fn row ->
        {row.date, %{total: row.total, successful: row.successful, failed: row.failed}}
      end)

    empty = %{total: 0, successful: 0, failed: 0}

    start_dt
    |> daily_range(end_dt)
    |> Enum.map(fn date ->
      values = Map.get(by_date, date, empty)
      Map.put(values, :date, date)
    end)
  end

  @doc """
  Per-job queue-time aggregates over the window: avg, p50, p90, p99
  plus a daily series for each percentile. "Queue time" is the wall-
  clock gap between `enqueued_at` and `claimed_at` — how long a
  workflow_job waited before any runner picked it up. Jobs still in
  the queue (`claimed_at` at epoch) are excluded; they don't have a
  closed interval to measure yet.
  """
  def queue_time(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    current = queue_time_aggregates(account_id, start_dt, end_dt, opts)
    previous = queue_time_aggregates(account_id, prev_start_dt, prev_end_dt, opts)
    rows = queue_time_buckets_per_day(account_id, start_dt, end_dt, opts)
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

  defp queue_time_aggregates(account_id, start_dt, end_dt, opts) do
    [aggregates | _] =
      Job
      |> from(hints: ["FINAL"])
      |> claimed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
      |> select([j], %{
        avg:
          fragment(
            "avg(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.claimed_at,
            j.enqueued_at
          ),
        p50:
          fragment(
            "quantile(0.5)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.claimed_at,
            j.enqueued_at
          ),
        p90:
          fragment(
            "quantile(0.9)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.claimed_at,
            j.enqueued_at
          ),
        p99:
          fragment(
            "quantile(0.99)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
            j.claimed_at,
            j.enqueued_at
          )
      })
      |> ClickHouseRepo.all()
      |> default_empty(%{avg: 0, p50: 0, p90: 0, p99: 0})

    aggregates
  end

  defp queue_time_buckets_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> claimed_in_window(account_id, start_dt, end_dt)
    |> scope_workflow(opts)
    |> group_by([j], fragment("toDate(?)", j.claimed_at))
    |> order_by([j], asc: fragment("toDate(?)", j.claimed_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.claimed_at),
      avg:
        fragment(
          "avg(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.claimed_at,
          j.enqueued_at
        ),
      p50:
        fragment(
          "quantile(0.5)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.claimed_at,
          j.enqueued_at
        ),
      p90:
        fragment(
          "quantile(0.9)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.claimed_at,
          j.enqueued_at
        ),
      p99:
        fragment(
          "quantile(0.99)(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
          j.claimed_at,
          j.enqueued_at
        )
    })
    |> ClickHouseRepo.all()
  end

  # Jobs that left the queue in the window — `claimed_at` past epoch
  # within `[start_dt, end_dt]`. We bucket on `claimed_at` (not
  # `enqueued_at`) so a job enqueued just before the window but
  # claimed inside it still contributes to the day it was picked up.
  defp claimed_in_window(query, account_id, start_dt, end_dt) do
    where(
      query,
      [j],
      j.account_id == ^account_id and j.claimed_at >= ^start_dt and j.claimed_at <= ^end_dt and
        fragment("toUnixTimestamp64Milli(?) > 0", j.enqueued_at) and
        fragment("toUnixTimestamp64Milli(?) > 0", j.claimed_at)
    )
  end

  @doc """
  Total distinct workflow_runs over the window plus a daily series
  and the trend (% change) versus the previous equivalent window. A
  workflow_run is one full CI invocation — many jobs share the same
  `workflow_run_id`, but the count is over distinct ids so a run with
  twenty matrix jobs still counts once.
  """
  def workflow_runs_count(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    count = workflow_runs_count_in_range(account_id, start_dt, end_dt, opts)
    previous_count = workflow_runs_count_in_range(account_id, prev_start_dt, prev_end_dt, opts)

    rows = workflow_runs_per_day(account_id, start_dt, end_dt, opts)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp workflow_runs_count_in_range(account_id, start_dt, end_dt, opts) do
    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where(
        [j],
        j.account_id == ^account_id and j.enqueued_at >= ^start_dt and
          j.enqueued_at <= ^end_dt and j.workflow_run_id > 0
      )
      |> scope_workflow(opts)
      |> select([j], %{count: fragment("uniqExact(?)", j.workflow_run_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count || 0
  end

  defp workflow_runs_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where(
      [j],
      j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt and
        j.workflow_run_id > 0
    )
    |> scope_workflow(opts)
    |> group_by([j], fragment("toDate(?)", j.enqueued_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.enqueued_at),
      value: fragment("uniqExact(?)", j.workflow_run_id)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.enqueued_at))
    |> ClickHouseRepo.all()
  end

  @doc """
  Count of workflow_runs whose roll-up landed on failure — at least
  one job in the run completed with `conclusion='failure'`. Daily
  series + trend match the shape of `workflow_runs_count/2` so both
  widgets can switch the same chart pattern.
  """
  def failed_workflow_runs_count(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)

    count = failed_workflow_runs_in_range(account_id, start_dt, end_dt, opts)
    previous_count = failed_workflow_runs_in_range(account_id, prev_start_dt, prev_end_dt, opts)
    rows = failed_workflow_runs_per_day(account_id, start_dt, end_dt, opts)
    filled = fill_dates(rows, start_dt, end_dt, &Map.get(&1, :value, 0))

    %{
      count: count,
      trend: trend(previous_count, count),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  defp failed_workflow_runs_in_range(account_id, start_dt, end_dt, opts) do
    [%{count: count} | _] =
      account_id
      |> failed_workflow_runs_base_query(start_dt, end_dt, opts)
      |> select([j], %{count: fragment("uniqExact(?)", j.workflow_run_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count || 0
  end

  defp failed_workflow_runs_per_day(account_id, start_dt, end_dt, opts) do
    account_id
    |> failed_workflow_runs_base_query(start_dt, end_dt, opts)
    |> group_by([j], fragment("toDate(?)", j.enqueued_at))
    |> select([j], %{
      date: fragment("toDate(?)", j.enqueued_at),
      value: fragment("uniqExact(?)", j.workflow_run_id)
    })
    |> order_by([j], asc: fragment("toDate(?)", j.enqueued_at))
    |> ClickHouseRepo.all()
  end

  # A workflow_run is "failed" when any of its jobs completed with
  # `conclusion='failure'`. We filter rows directly rather than rolling
  # the run up first because `uniqExact(workflow_run_id)` over the
  # filtered rows produces the same distinct count without the extra
  # subquery roundtrip.
  defp failed_workflow_runs_base_query(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> where(
      [j],
      j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt and
        j.workflow_run_id > 0 and j.status == "completed" and j.conclusion == "failure"
    )
    |> scope_workflow(opts)
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

    current = workflows_duration_aggregates(account_id, start_dt, end_dt, opts)
    previous = workflows_duration_aggregates(account_id, prev_start_dt, prev_end_dt, opts)
    rows = workflows_duration_per_day(account_id, start_dt, end_dt, opts)
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

  defp workflows_duration_aggregates(account_id, start_dt, end_dt, opts) do
    runs_subquery = workflow_runs_subquery(account_id, start_dt, end_dt, opts)

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

  defp workflows_duration_per_day(account_id, start_dt, end_dt, opts) do
    runs_subquery = workflow_runs_subquery(account_id, start_dt, end_dt, opts)

    ClickHouseRepo.all(
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
    )
  end

  defp workflow_runs_subquery(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> completed_in_window(account_id, start_dt, end_dt)
    |> scope_workflow(opts)
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

  defp duration_buckets_per_day(account_id, start_dt, end_dt, opts) do
    Job
    |> from(hints: ["FINAL"])
    |> completed_in_window(account_id, start_dt, end_dt)
    |> scope_workflow(opts)
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

  @scatter_data_limit 10_000

  @doc """
  Returns one point per completed workflow_job for the scatter
  view of the Job duration chart. Each point carries the
  completed_at as the x value (ms since epoch) and the runtime in
  seconds as the y value. Results are capped at #{@scatter_data_limit}
  and grouped into a single series so the same Noora `scatter_chart`
  component the builds page already uses can render them.
  """
  def job_duration_scatter(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

    rows =
      Job
      |> from(hints: ["FINAL"])
      |> completed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
      |> select([j], %{
        id: j.workflow_job_id,
        completed_at: j.completed_at,
        duration_ms:
          fragment(
            "toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)",
            j.completed_at,
            j.started_at
          ),
        conclusion: j.conclusion
      })
      |> order_by([j], desc: j.completed_at)
      |> limit(@scatter_data_limit)
      |> ClickHouseRepo.all()

    points_to_scatter_payload(rows)
  end

  @doc """
  Same shape as `job_duration_scatter/2` but for the queue-time
  chart — x = `claimed_at`, y = `(claimed_at - enqueued_at) / 1000`.
  """
  def queue_time_scatter(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

    rows =
      Job
      |> from(hints: ["FINAL"])
      |> claimed_in_window(account_id, start_dt, end_dt)
      |> scope_workflow(opts)
      |> select([j], %{
        id: j.workflow_job_id,
        completed_at: j.claimed_at,
        duration_ms:
          fragment(
            "toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)",
            j.claimed_at,
            j.enqueued_at
          ),
        conclusion: j.conclusion
      })
      |> order_by([j], desc: j.claimed_at)
      |> limit(@scatter_data_limit)
      |> ClickHouseRepo.all()

    points_to_scatter_payload(rows)
  end

  defp points_to_scatter_payload(rows) do
    truncated = length(rows) >= @scatter_data_limit
    oldest_entry = if truncated, do: rows |> List.last() |> Map.get(:completed_at)

    data =
      Enum.map(rows, fn row ->
        ts = DateTime.to_unix(row.completed_at, :millisecond)
        seconds = Float.round(row.duration_ms / 1000, 1)

        %{
          value: [ts, seconds],
          id: row.id,
          meta: %{conclusion: row.conclusion}
        }
      end)

    %{
      series: [%{name: "duration", data: data}],
      truncated: truncated,
      oldest_entry: maybe_to_naive(oldest_entry)
    }
  end

  defp maybe_to_naive(nil), do: nil
  defp maybe_to_naive(%DateTime{} = dt), do: DateTime.to_naive(dt)
  defp maybe_to_naive(%NaiveDateTime{} = nd), do: nd

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

    start_dt
    |> daily_range(end_dt)
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

    start_dt
    |> daily_range(end_dt)
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

  # Narrows a `runner_jobs` query to a specific workflow when the
  # caller provides `:repo` and/or `:workflow_name` opts. Used by the
  # workflow detail page to reuse the same widget queries that power
  # the Jobs page, only scoped to one (repo, workflow_name) pair.
  # The same opts also carry an optional `:platform` ("macos" or
  # "linux") which narrows on the `fleet_name` prefix — no new
  # column needed since every fleet is already named after its OS
  # (macos-xcode-26.4, linux-amd64, etc.).
  defp scope_workflow(query, opts) do
    query
    |> maybe_eq(:repo, Keyword.get(opts, :repo))
    |> maybe_eq(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_platform(Keyword.get(opts, :platform))
  end

  defp maybe_platform(query, nil), do: query
  defp maybe_platform(query, ""), do: query
  defp maybe_platform(query, "any"), do: query

  defp maybe_platform(query, platform) when platform in ["macos", "linux"] do
    prefix = platform <> "-"
    where(query, [j], fragment("startsWith(?, ?)", j.fleet_name, ^prefix))
  end

  defp maybe_platform(query, _), do: query

  defp maybe_eq(query, _field, nil), do: query
  defp maybe_eq(query, _field, ""), do: query

  defp maybe_eq(query, :repo, value) when is_binary(value), do: where(query, [j], j.repo == ^value)

  defp maybe_eq(query, :workflow_name, value) when is_binary(value), do: where(query, [j], j.workflow_name == ^value)
end
