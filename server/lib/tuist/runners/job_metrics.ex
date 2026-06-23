defmodule Tuist.Runners.JobMetrics do
  @moduledoc """
  ClickHouse-backed store for runner-job machine metrics. Writes are
  batch INSERTs from the runner metrics collector (POSTed via
  `TuistWeb.RunnerJobMetricsController`); reads serve the job detail
  page's Overview charts and Metrics tab.

  Re-delivered collector batches collapse on the ReplacingMergeTree
  `(workflow_job_id, timestamp)` key with `inserted_at` as the
  version, so an at-least-once retry is a no-op merge.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobMachineMetric

  @float_fields [:cpu_usage_percent, :cpu_iowait_percent]
  @integer_fields [
    :memory_used_bytes,
    :memory_total_bytes,
    :network_bytes_in,
    :network_bytes_out,
    :disk_used_bytes,
    :disk_total_bytes
  ]
  @sample_fields @float_fields ++ @integer_fields

  @doc """
  Inserts a batch of metric samples for a job. Each sample carries
  `:timestamp` (epoch seconds) plus any subset of `#{inspect(@sample_fields)}`;
  missing fields default to `0`. `:inserted_at` is stamped here as
  the RMT version so a retried batch resolves to the latest write.

  An empty sample list is a no-op.
  """
  def record(_workflow_job_id, _account_id, []), do: :ok

  def record(workflow_job_id, account_id, samples)
      when is_integer(workflow_job_id) and is_integer(account_id) and is_list(samples) do
    now = DateTime.utc_now()

    rows =
      Enum.map(samples, fn sample ->
        @sample_fields
        |> Map.new(fn field -> {field, coerce(field, Map.get(sample, field, 0))} end)
        |> Map.merge(%{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          timestamp: Map.fetch!(sample, :timestamp) / 1,
          inserted_at: now
        })
      end)

    IngestRepo.insert_all(JobMachineMetric, rows)
    :ok
  end

  # The `Float32`/`Int64` ClickHouse columns reject the wrong numeric
  # kind on dump (an integer `0` default won't go into `Float32`), so
  # coerce each value to its column's type before insert.
  defp coerce(field, value) when field in @float_fields, do: value / 1
  defp coerce(field, value) when field in @integer_fields, do: trunc(value)

  @doc """
  Lists a job's metric samples in time order. Returns maps with
  `:timestamp` and every field in `#{inspect(@sample_fields)}`.

  Uses `argMax(col, inserted_at) GROUP BY (workflow_job_id, timestamp)`
  so a re-delivered batch collapses to one row per timestamp without
  paying for `FINAL`'s part merge — the same pattern `JobSteps` uses.
  """
  def list_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    ClickHouseRepo.all(
      from(m in JobMachineMetric,
        where: m.workflow_job_id == ^workflow_job_id,
        group_by: [m.workflow_job_id, m.timestamp],
        order_by: [asc: m.timestamp],
        select: %{
          timestamp: m.timestamp,
          cpu_usage_percent: fragment("argMax(?, ?)", m.cpu_usage_percent, m.inserted_at),
          cpu_iowait_percent: fragment("argMax(?, ?)", m.cpu_iowait_percent, m.inserted_at),
          memory_used_bytes: fragment("argMax(?, ?)", m.memory_used_bytes, m.inserted_at),
          memory_total_bytes: fragment("argMax(?, ?)", m.memory_total_bytes, m.inserted_at),
          network_bytes_in: fragment("argMax(?, ?)", m.network_bytes_in, m.inserted_at),
          network_bytes_out: fragment("argMax(?, ?)", m.network_bytes_out, m.inserted_at),
          disk_used_bytes: fragment("argMax(?, ?)", m.disk_used_bytes, m.inserted_at),
          disk_total_bytes: fragment("argMax(?, ?)", m.disk_total_bytes, m.inserted_at)
        }
      )
    )
  end
end
