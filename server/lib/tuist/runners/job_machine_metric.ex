defmodule Tuist.Runners.JobMachineMetric do
  @moduledoc """
  One machine-metrics sample for a runner job. Stored in ClickHouse
  (`runner_job_machine_metrics`) as a ReplacingMergeTree row per
  `(workflow_job_id, timestamp)` so a re-delivered collector batch
  collapses on merge. See `Tuist.Runners.JobMetrics` for the
  read/write contract and
  `Tuist.IngestRepo.Migrations.CreateRunnerJobMachineMetrics` for the
  schema rationale.
  """
  use Ecto.Schema

  @primary_key false

  schema "runner_job_machine_metrics" do
    field :workflow_job_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :timestamp, Ch, type: "Float64"
    field :cpu_usage_percent, Ch, type: "Float32", default: 0.0
    field :cpu_iowait_percent, Ch, type: "Float32", default: 0.0
    field :memory_used_bytes, Ch, type: "Int64", default: 0
    field :memory_total_bytes, Ch, type: "Int64", default: 0
    field :network_bytes_in, Ch, type: "Int64", default: 0
    field :network_bytes_out, Ch, type: "Int64", default: 0
    field :disk_used_bytes, Ch, type: "Int64", default: 0
    field :disk_total_bytes, Ch, type: "Int64", default: 0
    # Nullable, unlike every other metric here: on this column 0 is a real
    # reading (the volume is full), so it must stay distinguishable from a
    # runner image that predates the field. See the migration for why
    # `total - used` cannot substitute for it on APFS.
    field :disk_available_bytes, Ch, type: "Nullable(Int64)"
    field :inserted_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
