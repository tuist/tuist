defmodule Cache.DistributedKV.Repo.Migrations.SplitCleanupState do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :active_cleanup_cutoff_at, :timestamptz
      add :published_cleanup_generation, :integer
      add :published_cleanup_cutoff_at, :timestamptz
      add :cleanup_published_at, :timestamptz
      add :cleanup_event_id, :bigint
    end

    execute(
      """
      UPDATE projects
      SET
        active_cleanup_cutoff_at = CASE
          WHEN cleanup_lease_expires_at IS NOT NULL AND cleanup_lease_expires_at > clock_timestamp()
          THEN last_cleanup_at
          ELSE NULL
        END,
        published_cleanup_generation = CASE WHEN last_cleanup_at IS NULL THEN NULL ELSE 1 END,
        published_cleanup_cutoff_at = date_trunc('second', last_cleanup_at),
        cleanup_published_at = last_cleanup_at
      """,
      "UPDATE projects SET last_cleanup_at = COALESCE(active_cleanup_cutoff_at, published_cleanup_cutoff_at)"
    )

    alter table(:projects) do
      remove :last_cleanup_at, :timestamptz, null: false
    end

    execute(
      "ALTER TABLE projects ALTER COLUMN cleanup_lease_expires_at DROP NOT NULL",
      "ALTER TABLE projects ALTER COLUMN cleanup_lease_expires_at SET NOT NULL"
    )

    create index(:projects, [:cleanup_event_id], where: "cleanup_event_id IS NOT NULL")

    create index(:key_value_entries, [:account_handle, :project_handle, :source_updated_at, :key])

    execute(
      "CREATE SEQUENCE IF NOT EXISTS cleanup_event_id_seq",
      "DROP SEQUENCE IF EXISTS cleanup_event_id_seq"
    )
  end
end
