defmodule Tuist.Runners.JobSteps do
  @moduledoc """
  ClickHouse-backed store for workflow_job steps. Writes are batch
  INSERTs from the `workflow_job.completed` webhook (the only event
  on which GitHub populates the steps array); reads serve the job
  detail page's Steps card and — once dashboards land — step-level
  analytics (failure rate per step name, p95 of `Build` duration,
  slowest steps in a workflow).

  Webhook retries collapse on the ReplacingMergeTree `(workflow_job_id,
  number)` key with `inserted_at` as the version, so a redelivered
  `workflow_job.completed` is a no-op merge.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobStep

  @doc """
  Inserts the workflow_job's full step list. Each map carries `:number`,
  `:name`, `:status`, `:conclusion`, `:started_at`, `:completed_at`.
  `:inserted_at` is stamped here as the RMT version so a retried
  delivery resolves to the latest write.

  An empty step list is a no-op — GitHub occasionally delivers
  `workflow_job.completed` without a populated steps array (e.g. on
  cancelled jobs), and an empty INSERT would still bump partitions.
  """
  def record([]), do: :ok

  def record(steps) when is_list(steps) do
    now = DateTime.utc_now()

    rows = Enum.map(steps, &Map.put(&1, :inserted_at, now))
    IngestRepo.insert_all(JobStep, rows)
    :ok
  end

  @doc """
  Lists a job's steps in display order. Returns maps with `:number`,
  `:name`, `:status`, `:conclusion`, `:started_at`, `:completed_at`.

  `FINAL` is cheap here because every query is scoped to a single
  `workflow_job_id` (the order-key prefix), and a job has tens of
  steps at most.
  """
  def list_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    JobStep
    |> from(hints: ["FINAL"])
    |> where([s], s.workflow_job_id == ^workflow_job_id)
    |> order_by([s], asc: s.number)
    |> select([s], %{
      number: s.number,
      name: s.name,
      status: s.status,
      conclusion: s.conclusion,
      started_at: s.started_at,
      completed_at: s.completed_at
    })
    |> ClickHouseRepo.all()
  end
end
