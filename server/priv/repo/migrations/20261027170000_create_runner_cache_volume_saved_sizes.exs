defmodule Tuist.Repo.Migrations.CreateRunnerCacheVolumeSavedSizes do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create table(:runner_cache_volume_saved_sizes) do
      add(:volume_id, references(:runner_cache_volumes, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:size_bytes, :bigint)
      add(:observed_at, :timestamptz, null: false)
    end

    create(
      index(:runner_cache_volume_saved_sizes, [:volume_id, :observed_at, :id], concurrently: true)
    )

    # Only establish what is known now; retained copies cannot reconstruct past HEADs.
    # Inserts into the new table without modifying existing volume rows.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    INSERT INTO runner_cache_volume_saved_sizes (volume_id, size_bytes, observed_at)
    SELECT v.id, CASE WHEN v.head_id IS NULL THEN 0 ELSE u.size_bytes END, statement_timestamp()
    FROM runner_cache_volumes v
    LEFT JOIN runner_cache_volume_uses u ON u.id = v.head_id
    """)
  end

  def down do
    # Roll back the application first; only the newly introduced analytics are removed.
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop(table(:runner_cache_volume_saved_sizes))
  end
end
