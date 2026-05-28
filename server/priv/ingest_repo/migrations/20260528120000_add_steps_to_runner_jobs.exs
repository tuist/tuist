defmodule Tuist.IngestRepo.Migrations.AddStepsToRunnerJobs do
  use Ecto.Migration

  # Stores the workflow_job's steps as a JSON array, captured from
  # the `workflow_job.completed` webhook (GitHub only populates the
  # `steps` array once the job finishes). Each entry carries the
  # step name, status, conclusion, number, and start/finish
  # timestamps so the job detail page can render the per-step
  # breakdown GitHub's own UI shows.
  #
  # Plain `String` holding JSON rather than a typed `Nested` column:
  # steps are only ever read back whole for a single job, never
  # filtered or aggregated, so a blob avoids the per-part dictionary
  # and column-fan-out cost of `Nested` for zero query benefit.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS steps String DEFAULT ''
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS steps")
  end
end
