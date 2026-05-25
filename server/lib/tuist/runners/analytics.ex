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

  ## Why we don't use `FINAL`

  `runner_jobs` is a ReplacingMergeTree. The classic
  `FROM runner_jobs FINAL` selects the latest version per
  `workflow_job_id`, but the merge runs at query time across every
  unmerged part — single-threaded per part — and gets dramatically
  more expensive as state-transition INSERTs pile up. For analytics
  workloads the canonical pattern is a GROUP BY + argMax subquery
  that picks the latest version once, then aggregates over the
  collapsed view. That's what `latest_jobs_enqueued_between/4` and
  `latest_jobs_claimed_between/4` do — every analytics function in
  this module dedupes once via a subquery and never asks ClickHouse
  to merge parts at read time.
  """

  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Runners.Job
  alias Tuist.Utilities.DateFormatter

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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [%{count: count} | _] =
      from(j in subquery(sub), select: %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count
  end

  defp jobs_count_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      group_by: fragment("toDate(?)", j.enqueued_at),
      order_by: fragment("toDate(?)", j.enqueued_at),
      select: %{
        date: fragment("toDate(?)", j.enqueued_at),
        value: count(j.workflow_job_id)
      }
    )
    |> ClickHouseRepo.all()
  end

  @doc """
  Total count of failed jobs over the window + daily series + trend.
  A "failed" job is one whose latest state is `completed`/`failure`.
  Cancelled/skipped don't count — the customer cares about
  runner-attributable failures, not the build-author's choices.
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [%{count: count} | _] =
      from(j in subquery(sub),
        where: j.status == "completed" and j.conclusion == "failure",
        select: %{count: count(j.workflow_job_id)}
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count
  end

  defp failed_jobs_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      where: j.status == "completed" and j.conclusion == "failure",
      group_by: fragment("toDate(?)", j.completed_at),
      order_by: fragment("toDate(?)", j.completed_at),
      select: %{
        date: fragment("toDate(?)", j.completed_at),
        value: count(j.workflow_job_id)
      }
    )
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

    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    rows =
      from(j in subquery(sub),
        where: j.status == "completed" and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
        group_by: fragment("toDate(?)", j.completed_at),
        order_by: fragment("toDate(?)", j.completed_at),
        select: %{
          date: fragment("toDate(?)", j.completed_at),
          value:
            fragment(
              "sum(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
              j.completed_at,
              j.started_at
            )
        }
      )
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [%{total_ms: total_ms} | _] =
      from(j in subquery(sub),
        where: j.status == "completed" and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
        select: %{
          total_ms:
            fragment(
              "sum(toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?))",
              j.completed_at,
              j.started_at
            )
        }
      )
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [aggregates | _] =
      from(j in subquery(sub),
        where: j.status == "completed" and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
        select: %{
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
        }
      )
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [aggregates | _] =
      from(j in subquery(sub),
        select: %{
          total: count(j.workflow_job_id),
          successful: fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
          failed: fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion)
        }
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{total: 0, successful: 0, failed: 0})

    aggregates
  end

  defp breakdown_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      group_by: fragment("toDate(?)", j.enqueued_at),
      order_by: fragment("toDate(?)", j.enqueued_at),
      select: %{
        date: fragment("toDate(?)", j.enqueued_at),
        total: count(j.workflow_job_id),
        successful: fragment("countIf(? = 'completed' AND ? = 'success')", j.status, j.conclusion),
        failed: fragment("countIf(? = 'completed' AND ? = 'failure')", j.status, j.conclusion)
      }
    )
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
    sub = latest_jobs_claimed_between(account_id, start_dt, end_dt, opts)

    [aggregates | _] =
      from(j in subquery(sub),
        select: %{
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
        }
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{avg: 0, p50: 0, p90: 0, p99: 0})

    aggregates
  end

  defp queue_time_buckets_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_claimed_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      group_by: fragment("toDate(?)", j.claimed_at),
      order_by: fragment("toDate(?)", j.claimed_at),
      select: %{
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
      }
    )
    |> ClickHouseRepo.all()
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [%{count: count} | _] =
      from(j in subquery(sub),
        where: j.workflow_run_id > 0,
        select: %{count: fragment("uniqExact(?)", j.workflow_run_id)}
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count || 0
  end

  defp workflow_runs_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      where: j.workflow_run_id > 0,
      group_by: fragment("toDate(?)", j.enqueued_at),
      order_by: fragment("toDate(?)", j.enqueued_at),
      select: %{
        date: fragment("toDate(?)", j.enqueued_at),
        value: fragment("uniqExact(?)", j.workflow_run_id)
      }
    )
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    [%{count: count} | _] =
      from(j in subquery(sub),
        where:
          j.workflow_run_id > 0 and j.status == "completed" and j.conclusion == "failure",
        select: %{count: fragment("uniqExact(?)", j.workflow_run_id)}
      )
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    count || 0
  end

  defp failed_workflow_runs_per_day(account_id, start_dt, end_dt, opts) do
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      where:
        j.workflow_run_id > 0 and j.status == "completed" and j.conclusion == "failure",
      group_by: fragment("toDate(?)", j.enqueued_at),
      order_by: fragment("toDate(?)", j.enqueued_at),
      select: %{
        date: fragment("toDate(?)", j.enqueued_at),
        value: fragment("uniqExact(?)", j.workflow_run_id)
      }
    )
    |> ClickHouseRepo.all()
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
    latest = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(latest),
      where:
        j.status == "completed" and j.workflow_run_id > 0 and
          fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
          fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
      group_by: j.workflow_run_id,
      select: %{
        completion_date: fragment("toDate(max(?))", j.completed_at),
        run_ms:
          fragment(
            "toUnixTimestamp64Milli(max(?)) - toUnixTimestamp64Milli(min(?))",
            j.completed_at,
            j.started_at
          )
      }
    )
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
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    from(j in subquery(sub),
      where: j.status == "completed" and
               fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
               fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
      group_by: fragment("toDate(?)", j.completed_at),
      order_by: fragment("toDate(?)", j.completed_at),
      select: %{
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
      }
    )
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
    group_by = group_by_opt(Keyword.get(opts, :group_by))
    sub = latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts)

    rows =
      from(j in subquery(sub),
        where: j.status == "completed" and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.started_at) and
                 fragment("toUnixTimestamp64Milli(?) > 0", j.completed_at),
        order_by: [desc: j.completed_at],
        limit: ^@scatter_data_limit,
        select: %{
          id: j.workflow_job_id,
          x_at: j.completed_at,
          duration_ms:
            fragment(
              "toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)",
              j.completed_at,
              j.started_at
            ),
          job_name: j.job_name,
          workflow_name: j.workflow_name,
          repo: j.repo,
          head_branch: j.head_branch,
          conclusion: j.conclusion,
          fleet_name: j.fleet_name
        }
      )
      |> ClickHouseRepo.all()

    points_to_scatter_payload(rows, group_by)
  end

  @doc """
  Same shape as `job_duration_scatter/2` but for the queue-time
  chart — x = `claimed_at`, y = `(claimed_at - enqueued_at) / 1000`.
  """
  def queue_time_scatter(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    group_by = group_by_opt(Keyword.get(opts, :group_by))
    sub = latest_jobs_claimed_between(account_id, start_dt, end_dt, opts)

    rows =
      from(j in subquery(sub),
        order_by: [desc: j.claimed_at],
        limit: ^@scatter_data_limit,
        select: %{
          id: j.workflow_job_id,
          x_at: j.claimed_at,
          duration_ms:
            fragment(
              "toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)",
              j.claimed_at,
              j.enqueued_at
            ),
          job_name: j.job_name,
          workflow_name: j.workflow_name,
          repo: j.repo,
          head_branch: j.head_branch,
          conclusion: j.conclusion,
          fleet_name: j.fleet_name
        }
      )
      |> ClickHouseRepo.all()

    points_to_scatter_payload(rows, group_by)
  end

  defp group_by_opt(:status), do: :status
  defp group_by_opt(:platform), do: :platform
  defp group_by_opt("status"), do: :status
  defp group_by_opt("platform"), do: :platform
  defp group_by_opt(_), do: nil

  defp points_to_scatter_payload(rows, group_by) do
    truncated = length(rows) >= @scatter_data_limit
    oldest_entry = if truncated, do: rows |> List.last() |> Map.get(:x_at)

    points =
      Enum.map(rows, fn row ->
        ts = DateTime.to_unix(row.x_at, :millisecond)
        seconds = Float.round(row.duration_ms / 1000, 1)

        %{
          value: [ts, seconds],
          id: row.id,
          group_key: group_key(row, group_by),
          tooltipExtra: tooltip_extra(row)
        }
      end)

    %{
      series: build_series(points, group_by),
      truncated: truncated,
      oldest_entry: maybe_to_naive(oldest_entry)
    }
  end

  # No `group_by` → every dot lives on one "duration" series. With
  # group_by set the points fan out into one series per group key,
  # which echarts paints with distinct colours and exposes as legend
  # chips — same UX as Group by Scheme on the Xcode builds page.
  defp build_series(points, nil) do
    [%{name: "duration", data: Enum.map(points, &Map.delete(&1, :group_key))}]
  end

  defp build_series(points, _group_by) do
    points
    |> Enum.group_by(& &1.group_key)
    |> Enum.map(fn {key, group_points} ->
      %{name: key, data: Enum.map(group_points, &Map.delete(&1, :group_key))}
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp group_key(_row, nil), do: nil
  defp group_key(row, :status), do: status_label(row.conclusion)
  defp group_key(row, :platform), do: platform_from_fleet(row.fleet_name)

  defp status_label(""), do: dgettext("dashboard_runners", "Unknown")
  defp status_label(nil), do: dgettext("dashboard_runners", "Unknown")
  defp status_label("success"), do: dgettext("dashboard_runners", "Success")
  defp status_label("failure"), do: dgettext("dashboard_runners", "Failure")
  defp status_label("cancelled"), do: dgettext("dashboard_runners", "Cancelled")
  defp status_label("skipped"), do: dgettext("dashboard_runners", "Skipped")
  defp status_label(other) when is_binary(other), do: String.capitalize(other)

  # Same prefix-derivation the page-level Platform filter uses, so
  # the Group by partition aligns with the dropdown filter scope.
  # Anything outside the two named OSes falls into "Other" so legacy
  # rows stay visible without being lumped in with the known fleets.
  defp platform_from_fleet(name) when is_binary(name) do
    cond do
      String.starts_with?(name, "macos-") -> dgettext("dashboard_runners", "macOS")
      String.starts_with?(name, "linux-") -> dgettext("dashboard_runners", "Linux")
      true -> dgettext("dashboard_runners", "Other")
    end
  end

  defp platform_from_fleet(_), do: dgettext("dashboard_runners", "Other")

  # Each dot carries enough context to identify the workflow_job
  # without leaving the chart — which workflow_run it belongs to,
  # which job, on which repo and branch, what status it ended in,
  # which platform executed it. Same per-row data the Recent jobs
  # table already exposes; the tooltip is the chart-equivalent of
  # that row.
  defp tooltip_extra(row) do
    [
      %{label: dgettext("dashboard_runners", "Workflow"), value: display(row.workflow_name)},
      %{label: dgettext("dashboard_runners", "Job"), value: display(row.job_name)},
      %{label: dgettext("dashboard_runners", "Repository"), value: display(row.repo)},
      %{label: dgettext("dashboard_runners", "Branch"), value: display(row.head_branch)},
      %{label: dgettext("dashboard_runners", "Status"), value: status_label(row.conclusion)},
      %{label: dgettext("dashboard_runners", "Platform"), value: platform_from_fleet(row.fleet_name)},
      %{label: dgettext("dashboard_runners", "Duration"), value: format_duration_ms(row.duration_ms)}
    ]
  end

  defp display(nil), do: dgettext("dashboard_runners", "Unknown")
  defp display(""), do: dgettext("dashboard_runners", "Unknown")
  defp display(value) when is_binary(value), do: value

  defp format_duration_ms(ms) when is_integer(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(ms)

  defp format_duration_ms(_), do: "0s"

  defp maybe_to_naive(nil), do: nil
  defp maybe_to_naive(%DateTime{} = dt), do: DateTime.to_naive(dt)
  defp maybe_to_naive(%NaiveDateTime{} = nd), do: nd

  # Returns a subquery containing one row per `workflow_job_id` for
  # the account, with each field collapsed to its latest version
  # (argMax over `updated_at`). The inner WHERE prunes by partition
  # via `enqueued_at` — partition-aligned on `toYYYYMM(enqueued_at)`
  # — and applies the workflow scope (repo / workflow_name /
  # platform) so we never carry rows we'll later drop. Use this for
  # every metric keyed off enqueued / completed time.
  defp latest_jobs_enqueued_between(account_id, start_dt, end_dt, opts) do
    Job
    |> where(
      [j],
      j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt
    )
    |> scope_workflow(opts)
    |> group_by([j], j.workflow_job_id)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
      status: fragment("argMax(?, ?)", j.status, j.updated_at),
      conclusion: fragment("argMax(?, ?)", j.conclusion, j.updated_at),
      enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at),
      claimed_at: fragment("argMax(?, ?)", j.claimed_at, j.updated_at),
      started_at: fragment("argMax(?, ?)", j.started_at, j.updated_at),
      completed_at: fragment("argMax(?, ?)", j.completed_at, j.updated_at),
      fleet_name: fragment("argMax(?, ?)", j.fleet_name, j.updated_at),
      workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
      job_name: fragment("argMax(?, ?)", j.job_name, j.updated_at),
      repo: fragment("argMax(?, ?)", j.repo, j.updated_at),
      head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at)
    })
  end

  # Variant for queue-time metrics, where the natural window is the
  # claim time rather than the enqueue time. Filters per-row by
  # `claimed_at` in [start, end] so we exclude the still-queued
  # versions (claimed_at = epoch) and any post-window rows. After
  # the GROUP BY the latest claimed_at is consistent across the
  # surviving rows (claimed_at is set once on transition and then
  # preserved by `job_to_row`).
  defp latest_jobs_claimed_between(account_id, start_dt, end_dt, opts) do
    Job
    |> where(
      [j],
      j.account_id == ^account_id and j.claimed_at >= ^start_dt and j.claimed_at <= ^end_dt and
        fragment("toUnixTimestamp64Milli(?) > 0", j.enqueued_at) and
        fragment("toUnixTimestamp64Milli(?) > 0", j.claimed_at)
    )
    |> scope_workflow(opts)
    |> group_by([j], j.workflow_job_id)
    |> select([j], %{
      workflow_job_id: j.workflow_job_id,
      workflow_run_id: fragment("argMax(?, ?)", j.workflow_run_id, j.updated_at),
      status: fragment("argMax(?, ?)", j.status, j.updated_at),
      conclusion: fragment("argMax(?, ?)", j.conclusion, j.updated_at),
      enqueued_at: fragment("argMax(?, ?)", j.enqueued_at, j.updated_at),
      claimed_at: fragment("argMax(?, ?)", j.claimed_at, j.updated_at),
      started_at: fragment("argMax(?, ?)", j.started_at, j.updated_at),
      completed_at: fragment("argMax(?, ?)", j.completed_at, j.updated_at),
      fleet_name: fragment("argMax(?, ?)", j.fleet_name, j.updated_at),
      workflow_name: fragment("argMax(?, ?)", j.workflow_name, j.updated_at),
      job_name: fragment("argMax(?, ?)", j.job_name, j.updated_at),
      repo: fragment("argMax(?, ?)", j.repo, j.updated_at),
      head_branch: fragment("argMax(?, ?)", j.head_branch, j.updated_at)
    })
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
