defmodule Tuist.Runners.JobLogs do
  @moduledoc """
  ClickHouse-backed per-line log store for runner jobs.

  Writes are append-only batches from the log-ingest endpoint
  (`IngestRepo.insert_all/2`); reads are single-job, time-windowed
  scans served by the `(workflow_job_id, line_number)` order key.

  The shipper delivers chunks at-least-once, so an append can repeat
  a `(workflow_job_id, line_number)` row on retry. The
  ReplacingMergeTree dedup on that key collapses the duplicate; reads
  use `FINAL` so the dedup is visible immediately. `FINAL` is cheap
  here because every query is scoped to a single `workflow_job_id`
  (the order-key prefix), unlike the multi-row `runner_jobs` reads
  that deliberately avoid it.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobLog

  @doc """
  Appends a batch of log lines. Each entry is a map carrying
  `:workflow_job_id`, `:account_id`, `:line_number`, `:ts`, and
  `:message`. `:inserted_at` is stamped here as the RMT version so
  a retried batch resolves to the latest write.
  """
  def append([]), do: :ok

  def append(lines) when is_list(lines) do
    now = DateTime.utc_now()

    rows = Enum.map(lines, &Map.put(&1, :inserted_at, now))
    IngestRepo.insert_all(JobLog, rows)
    :ok
  end

  @doc """
  Lists a job's log lines in display order. `:limit` / `:offset`
  page the stream — logs can be large, so callers window it. Returns
  maps with `:line_number`, `:ts`, `:message`.
  """
  def list_for_job(workflow_job_id, opts \\ []) when is_integer(workflow_job_id) do
    limit = Keyword.get(opts, :limit, 1000)
    offset = Keyword.get(opts, :offset, 0)

    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> order_by([l], asc: l.line_number)
    |> limit(^limit)
    |> offset(^offset)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
  end

  @doc """
  The most recent `limit` lines of a job, in ascending display order.
  This is what the Logs view loads on mount — a tail, not the whole
  stream — so a job with hundreds of thousands of lines doesn't pull
  them all into memory.
  """
  def recent(workflow_job_id, limit) when is_integer(workflow_job_id) and is_integer(limit) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> order_by([l], desc: l.line_number)
    |> limit(^limit)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  @doc """
  The `limit` lines immediately before `before_line_number`, ascending
  — the previous page when the user clicks "Load older logs".
  """
  def older(workflow_job_id, before_line_number, limit)
      when is_integer(workflow_job_id) and is_integer(before_line_number) and is_integer(limit) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number)
    |> order_by([l], desc: l.line_number)
    |> limit(^limit)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  @doc """
  Whether any line exists before `before_line_number` — drives the
  visibility of the "Load older logs" button.
  """
  def has_older?(_workflow_job_id, nil), do: false

  def has_older?(workflow_job_id, before_line_number)
      when is_integer(workflow_job_id) and is_integer(before_line_number) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number < ^before_line_number)
    |> select([l], 1)
    |> limit(1)
    |> ClickHouseRepo.one()
    |> is_integer()
  end

  @doc """
  Folds `fun` over a job's full log forward in batches (cursor on
  `line_number`), threading `acc` through. Used by the download
  endpoint to stream the whole log into a chunked response without
  materialising it in memory.
  """
  def reduce(workflow_job_id, batch_size, acc, fun)
      when is_integer(workflow_job_id) and is_integer(batch_size) and is_function(fun, 2) do
    reduce_from(workflow_job_id, 0, batch_size, acc, fun)
  end

  defp reduce_from(workflow_job_id, after_line_number, batch_size, acc, fun) do
    batch =
      JobLog
      |> from(hints: ["FINAL"])
      |> where([l], l.workflow_job_id == ^workflow_job_id and l.line_number > ^after_line_number)
      |> order_by([l], asc: l.line_number)
      |> limit(^batch_size)
      |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
      |> ClickHouseRepo.all()

    case batch do
      [] ->
        acc

      lines ->
        reduce_from(workflow_job_id, List.last(lines).line_number, batch_size, fun.(lines, acc), fun)
    end
  end

  @doc """
  Lists the log lines inside a step's `[started_at, completed_at)`
  window — the per-step slice the job detail page renders when a
  step is expanded.
  """
  def list_for_step(workflow_job_id, %DateTime{} = started_at, %DateTime{} = completed_at)
      when is_integer(workflow_job_id) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where(
      [l],
      l.workflow_job_id == ^workflow_job_id and l.ts >= ^started_at and l.ts < ^completed_at
    )
    |> order_by([l], asc: l.line_number)
    |> select([l], %{line_number: l.line_number, ts: l.ts, message: l.message})
    |> ClickHouseRepo.all()
  end

  @doc """
  Number of distinct log lines captured for a job.
  """
  def count_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    JobLog
    |> from(hints: ["FINAL"])
    |> where([l], l.workflow_job_id == ^workflow_job_id)
    |> select([l], count(l.line_number))
    |> ClickHouseRepo.one()
    |> Kernel.||(0)
  end

  @doc """
  Pub/Sub topic carrying live log chunks for a job. The ingest
  endpoint broadcasts newly appended lines here; the job detail
  LiveView subscribes for the live tail.
  """
  def topic(workflow_job_id) when is_integer(workflow_job_id), do: "runner_job_logs:#{workflow_job_id}"
end
