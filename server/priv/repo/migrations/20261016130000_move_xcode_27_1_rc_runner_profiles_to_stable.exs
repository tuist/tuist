defmodule Tuist.Repo.Migrations.MoveXcode271RcRunnerProfilesToStable do
  @moduledoc false
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(profile_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(queued_jobs_statement())
  end

  # Also used by the required post-rollout reconciliation, after old replicas
  # stop saving RC profiles and the last RC claims finish or release.
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
       AND NOT EXISTS (
         SELECT 1 FROM runner_claims c
          WHERE c.workflow_job_id = j.workflow_job_id
             OR c.executed_workflow_job_id = j.workflow_job_id
       )
    """
  end

  # The rollback chart must already support stable; never restore a retired pin.
  def down, do: :ok
end
