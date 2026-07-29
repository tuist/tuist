defmodule Tuist.IngestRepo.Migrations.AddWorkflowNameToRunnerJobs do
  use Ecto.Migration

  # Surfaces the GitHub workflow name (the `name:` field at the top
  # of the workflow file — e.g., "Server", "CLI") on the customer
  # Jobs dashboard. Pairs with the existing `job_name` to render a
  # familiar "<workflow> › <job>" breadcrumb on the runs list, and
  # powers the workflow filter.
  #
  # Plain `String` (not `LowCardinality`): workflow_name is
  # user-defined free-form input, so the per-part dictionary would
  # outgrow the ~10K-distinct sweet spot on any sizable account and
  # turn into compression / read overhead rather than a win.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS workflow_name String DEFAULT ''
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS workflow_name")
  end
end
