defmodule Tuist.IngestRepo.Migrations.AddRequestedDispatchLabelToRunnerJobs do
  use Ecto.Migration

  # Carries the customer's `runs-on:` label (e.g., `tuist-default`)
  # from webhook enqueue through to JIT-mint, so the runner registers
  # with GitHub under the same label the workflow_job requested.
  #
  # Required once profiles decouple the customer-facing label from
  # the pool's internal `dispatchLabel` (which now identifies a
  # shape-keyed pool like `shape-linux-4vcpu-16gb`, never seen by
  # customers).
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS requested_dispatch_label String DEFAULT ''
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS requested_dispatch_label")
  end
end
