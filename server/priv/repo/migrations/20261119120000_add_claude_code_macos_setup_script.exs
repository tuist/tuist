defmodule Tuist.Repo.Migrations.AddClaudeCodeMacosSetupScript do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # A Linux Claude Code environment can carry a macOS setup script that
  # prepares the Macs its sessions create with `create_sandbox`. Those
  # snapshots are kept per Xcode template, so a build is keyed by the
  # template too.
  def up do
    alter table(:sandbox_agent_environments) do
      add :macos_setup_script, :text
    end

    create unique_index(
             :sandbox_disk_snapshots,
             [:agent_environment_id, :repository, :setup_sha256, :template],
             name: :sandbox_disk_snapshots_repository_template_build_index,
             where: "state IN ('building', 'failed')",
             concurrently: true
           )

    drop index(:sandbox_disk_snapshots, [:agent_environment_id, :repository, :setup_sha256],
           name: :sandbox_disk_snapshots_repository_build_index,
           concurrently: true
         )
  end

  def down do
    # Builds of the same script for several templates would break the
    # narrower index.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DELETE FROM sandbox_disk_snapshots WHERE state IN ('building', 'failed')"

    create unique_index(
             :sandbox_disk_snapshots,
             [:agent_environment_id, :repository, :setup_sha256],
             name: :sandbox_disk_snapshots_repository_build_index,
             where: "state IN ('building', 'failed')",
             concurrently: true
           )

    drop index(
           :sandbox_disk_snapshots,
           [:agent_environment_id, :repository, :setup_sha256, :template],
           name: :sandbox_disk_snapshots_repository_template_build_index,
           concurrently: true
         )

    alter table(:sandbox_agent_environments) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :macos_setup_script
    end
  end
end
