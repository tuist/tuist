defmodule Tuist.Repo.Migrations.AddClaudeCodeRepositorySnapshots do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # A Claude Code environment can carry a setup script. A builder sandbox
  # runs it on a repository and saves the disks as a disk snapshot keyed by
  # the environment, the repository (`owner/name`) and the script's SHA-256,
  # so sessions boot repo-ready. Those snapshots have no Amp identifier. A
  # build in progress or recently failed is a row in state `building` or
  # `failed`; the partial unique index keeps one per key.
  def up do
    alter table(:sandbox_agent_environments) do
      add :setup_script, :text
    end

    alter table(:sandbox_disk_snapshots) do
      add :agent_environment_id, references(:sandbox_agent_environments, on_delete: :nilify_all)
      add :repository, :string
      add :setup_sha256, :string

      # Dropping NOT NULL only changes the catalog; the table is not rewritten.
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      modify :amp_snapshot_id, :string, null: true, from: {:string, null: false}
    end

    create index(:sandbox_disk_snapshots, [:agent_environment_id, :repository],
             concurrently: true
           )

    create unique_index(
             :sandbox_disk_snapshots,
             [:agent_environment_id, :repository, :setup_sha256],
             name: :sandbox_disk_snapshots_repository_build_index,
             where: "state IN ('building', 'failed')",
             concurrently: true
           )
  end

  def down do
    drop index(:sandbox_disk_snapshots, [:agent_environment_id, :repository, :setup_sha256],
           name: :sandbox_disk_snapshots_repository_build_index,
           concurrently: true
         )

    drop index(:sandbox_disk_snapshots, [:agent_environment_id, :repository], concurrently: true)

    # Claude Code snapshots have no Amp identifier. The nodes remove their
    # copies as orphans at their next reports; archived objects stay behind.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DELETE FROM sandbox_disk_snapshots WHERE amp_snapshot_id IS NULL"

    alter table(:sandbox_disk_snapshots) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :agent_environment_id
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :repository
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :setup_sha256
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :amp_snapshot_id, :string, null: false, from: {:string, null: true}
    end

    alter table(:sandbox_agent_environments) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :setup_script
    end
  end
end
