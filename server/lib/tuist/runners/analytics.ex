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
  Total job count over the window plus a daily series.

  Returns `%{count, dates, values}`.
  """
  def jobs_count(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

    [%{count: count} | _] =
      Job
      |> from(hints: ["FINAL"])
      |> where([j], j.account_id == ^account_id and j.enqueued_at >= ^start_dt and j.enqueued_at <= ^end_dt)
      |> select([j], %{count: count(j.workflow_job_id)})
      |> ClickHouseRepo.all()
      |> default_empty(%{count: 0})

    rows = jobs_count_per_day(account_id, start_dt, end_dt)

    %{
      count: count,
      dates: Enum.map(rows, & &1.date),
      values: Enum.map(rows, & &1.value)
    }
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
  milliseconds over the window, plus a daily series for the line
  chart. Used as the "Cumulative minutes" pricing surface.
  """
  def cumulative_minutes(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

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

    %{
      total_ms: total_ms || 0,
      dates: Enum.map(rows, & &1.date),
      values: Enum.map(rows, &(div(&1.value, 60_000) |> trunc()))
    }
  end

  @doc """
  Per-completed-job duration aggregates over the window: avg, p50,
  p90, p99, plus daily series for each percentile so the chart can
  switch with the percentile dropdown.
  """
  def jobs_duration(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

    [%{avg: avg, p50: p50, p90: p90, p99: p99} | _] =
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

    rows = duration_buckets_per_day(account_id, start_dt, end_dt, &job_duration_select/1)

    %{
      avg: trunc_or_zero(avg),
      p50: trunc_or_zero(p50),
      p90: trunc_or_zero(p90),
      p99: trunc_or_zero(p99),
      dates: Enum.map(rows, & &1.date),
      avg_values: Enum.map(rows, &trunc_or_zero(&1.avg)),
      p50_values: Enum.map(rows, &trunc_or_zero(&1.p50)),
      p90_values: Enum.map(rows, &trunc_or_zero(&1.p90)),
      p99_values: Enum.map(rows, &trunc_or_zero(&1.p99))
    }
  end

  @doc """
  Per-workflow_run duration aggregates. A workflow's duration is
  `max(completed_at) - min(started_at)` across the jobs that share a
  `workflow_run_id` — i.e. how long the whole CI run took from first
  start to last finish.
  """
  def workflows_duration(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)

    # Inner per-run subquery: one row per workflow_run_id with the
    # span from earliest start to latest completion.
    runs_subquery =
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

    [%{avg: avg, p50: p50, p90: p90, p99: p99} | _] =
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

    rows =
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

    %{
      avg: trunc_or_zero(avg),
      p50: trunc_or_zero(p50),
      p90: trunc_or_zero(p90),
      p99: trunc_or_zero(p99),
      dates: Enum.map(rows, & &1.date),
      avg_values: Enum.map(rows, &trunc_or_zero(&1.avg)),
      p50_values: Enum.map(rows, &trunc_or_zero(&1.p50)),
      p90_values: Enum.map(rows, &trunc_or_zero(&1.p90)),
      p99_values: Enum.map(rows, &trunc_or_zero(&1.p99))
    }
  end

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

  defp default_empty([], default), do: [default]
  defp default_empty(rows, _default), do: rows

  defp trunc_or_zero(nil), do: 0
  defp trunc_or_zero(value) when is_number(value), do: trunc(value)

  # Silence "unused alias" warnings; the select_fn parameter is kept
  # for future extensibility but `duration_buckets_per_day/4` ignores it.
  defp job_duration_select(_), do: :ok
end
