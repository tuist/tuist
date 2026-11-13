defmodule Tuist.Repo.Migrations.AllowSandboxRunnerCacheVolumeUses do
  use Ecto.Migration

  # A sandbox session's checkout use (`CacheVolumes.allocate_sandbox_checkout/3`)
  # belongs to no CI workflow job or run. Dropping NOT NULL rewrites nothing.
  def change do
    alter table(:runner_cache_volume_uses) do
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      modify :workflow_job_id, :bigint, null: true, from: {:bigint, null: false}
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      modify :workflow_run_id, :bigint, null: true, from: {:bigint, null: false}
    end
  end
end
