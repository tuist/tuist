defmodule Tuist.IngestRepo.Migrations.AddDiskAvailableToRunnerJobMachineMetrics do
  use Ecto.Migration

  # `disk_used_bytes` / `disk_total_bytes` cannot answer "did this job run the
  # volume out of space?".
  #
  # The collector reads them from `df` columns `Used` and `1024-blocks`, and on
  # APFS those do not subtract: the blocks column is the whole container, `Used`
  # is one volume's usage, and the remainder is held by the container's other
  # volumes, by snapshots and by purgeable space. `total - used` is therefore an
  # upper bound that can overstate what a build may actually write several times
  # over — measured on a developer Mac at 45.8 GB against 12.8 GB truly
  # available, with the volume at 98% capacity.
  #
  # The gap changed a diagnosis. A runner job that failed with
  # `No space left on device` was holding 64.3 GB used of 139.5 GB, while a job
  # that SUCCEEDED on the same image held 66.1 GB — more. Resident bytes simply
  # do not discriminate, and the number that would have is the one we never
  # stored.
  #
  # `Nullable` rather than `DEFAULT 0`, because on this column zero is the
  # interesting reading. Every other metric here defaults to 0 for collectors
  # that cannot measure it, which is safe when 0 means "nothing happened"; here
  # it would be indistinguishable from "the volume is full", the exact state we
  # added the column to catch. NULL means the runner image predates this field.
  def up do
    execute(
      "ALTER TABLE runner_job_machine_metrics ADD COLUMN IF NOT EXISTS disk_available_bytes Nullable(Int64)"
    )
  end

  def down do
    execute("ALTER TABLE runner_job_machine_metrics DROP COLUMN IF EXISTS disk_available_bytes")
  end
end
