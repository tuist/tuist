defmodule Tuist.Repo.Migrations.ReshapeMacosRunnerShapesToRackGuests do
  @moduledoc false
  use Ecto.Migration

  # The macOS catalog moves from 6 vCPU / 14 GB and 12 vCPU / 28 GB to
  # 8 vCPU / 24 GB and 16 vCPU / 48 GB, the guests the BER1 rack already
  # runs. The billing baseline moves with it, so a job costs what it did.
  #
  # Concurrency limits are vCPU and memory totals, so they scale by the
  # same ratios to keep admitting as many jobs as before: the default
  # 12 vCPU / 28 GB (two baseline jobs) becomes 16 vCPU / 48 GB.
  #
  # Shape values are inlined rather than read through
  # `Tuist.Runners.Catalog`: migrations must not depend on the runtime
  # catalog.

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(profile_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(limits_statement())

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(16, 48))

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(queued_jobs_statement())
  end

  # Also the post-rollout reconciliation: until the last old replica
  # stops, it still creates profiles at the old default shape and
  # dispatches an 8 vCPU / 24 GB profile to a `-8vcpu-24gb` pool that
  # never renders. Run `profile_statement/0` and `queued_jobs_statement/0`
  # again once the rollout finishes. Never rerun `limits_statement/0`: it
  # scales whatever it finds.
  def profile_statement do
    """
    UPDATE runner_profiles
       SET vcpus = CASE WHEN vcpus = 6 THEN 8 ELSE 16 END,
           memory_gb = CASE WHEN vcpus = 6 THEN 24 ELSE 48 END,
           updated_at = NOW()
     WHERE platform = 'macos'
       AND ((vcpus = 6 AND memory_gb = 14) OR (vcpus = 12 AND memory_gb = 28))
    """
  end

  def limits_statement do
    """
    UPDATE runner_concurrency_limits
       SET vcpus = CEIL(vcpus * 4 / 3.0)::integer,
           memory_gb = CEIL(memory_gb * 12 / 7.0)::integer,
           updated_at = NOW()
     WHERE platform = 'macos'
    """
  end

  # The default shape's pools carry no shape suffix and keep their names;
  # only the larger shape's pools are renamed.
  def queued_jobs_statement do
    """
    UPDATE runner_workflow_jobs j
       SET fleet_name = regexp_replace(j.fleet_name, '-(12vcpu-28gb|8vcpu-24gb)$', CASE WHEN j.fleet_name ~ '-12vcpu-28gb$' THEN '-16vcpu-48gb' ELSE '' END),
           updated_at = NOW()
     WHERE j.status = 'queued'
       AND j.fleet_name ~ '-macos-.*-(12vcpu-28gb|8vcpu-24gb)$'
       AND NOT EXISTS (
         SELECT 1 FROM runner_claims c
          WHERE c.workflow_job_id = j.workflow_job_id
             OR c.executed_workflow_job_id = j.workflow_job_id
       )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_profiles
       SET vcpus = CASE WHEN vcpus = 8 THEN 6 ELSE 12 END,
           memory_gb = CASE WHEN vcpus = 8 THEN 14 ELSE 28 END,
           updated_at = NOW()
     WHERE platform = 'macos'
       AND ((vcpus = 8 AND memory_gb = 24) OR (vcpus = 16 AND memory_gb = 48))
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_concurrency_limits
       SET vcpus = GREATEST(FLOOR(vcpus * 3 / 4.0), 1)::integer,
           memory_gb = GREATEST(FLOOR(memory_gb * 7 / 12.0), 1)::integer,
           updated_at = NOW()
     WHERE platform = 'macos'
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(default_limits_function(12, 28))
  end

  defp default_limits_function(macos_vcpus, macos_memory_gb) do
    """
    CREATE OR REPLACE FUNCTION create_default_runner_concurrency_limits()
    RETURNS trigger AS $$
    BEGIN
      INSERT INTO runner_concurrency_limits
        (account_id, platform, vcpus, memory_gb, inserted_at, updated_at)
      VALUES
        (NEW.id, 'linux', 32, 64, NOW(), NOW()),
        (NEW.id, 'macos', #{macos_vcpus}, #{macos_memory_gb}, NOW(), NOW())
      ON CONFLICT (account_id, platform) DO NOTHING;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
