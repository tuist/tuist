defmodule Tuist.IngestRepo.Migrations.DropStepsFromRunnerJobs do
  use Ecto.Migration

  # The JSON `steps` column on `runner_jobs` has been replaced by the
  # `runner_job_steps` table. The blob never had any consumers other
  # than the job detail page (one job at a time, parse and render);
  # promoting steps to rows lets step-level analytics — failure rate
  # per step name, p95 of `Build` duration, slowest steps in a
  # workflow — become SQL instead of application-level JSON parses.
  def up do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS steps")
  end

  def down do
    execute("ALTER TABLE runner_jobs ADD COLUMN IF NOT EXISTS steps String DEFAULT ''")
  end
end
