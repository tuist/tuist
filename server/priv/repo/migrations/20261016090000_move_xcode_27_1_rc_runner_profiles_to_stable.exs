defmodule Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStable do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(profile_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(queued_jobs_statement())
  end

  def profile_statement do
    """
    UPDATE runner_profiles
       SET xcode_version = '27.1', updated_at = NOW()
     WHERE platform = 'macos' AND xcode_version = '27.1-rc'
    """
  end

  def queued_jobs_statement do
    """
    UPDATE runner_workflow_jobs j
       SET fleet_name = regexp_replace(j.fleet_name, '-27-1-rc((-[0-9]+vcpu-[0-9]+gb)?)$', '-27-1\\1'),
           updated_at = NOW()
     WHERE j.status = 'queued'
       AND j.fleet_name ~ '-macos-([a-z0-9-]+-)?27-1-rc(-[0-9]+vcpu-[0-9]+gb)?$'
       AND NOT EXISTS (SELECT 1 FROM runner_claims c WHERE c.workflow_job_id = j.workflow_job_id)
    """
  end

  # Do not turn stable profiles back into pins to a retired pool on rollback.
  def down, do: :ok
end
