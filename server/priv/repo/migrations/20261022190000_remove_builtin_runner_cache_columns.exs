defmodule Tuist.Repo.Migrations.RemoveBuiltinRunnerCacheColumns do
  use Ecto.Migration

  def up do
    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :builtin_name
    end

    alter table(:runner_cache_volume_uses) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :superseded_at
    end

    alter table(:runner_cache_volume_measurements) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :retired
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE runner_volume_heads ALTER COLUMN volume_name DROP DEFAULT"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE runner_volume_master_orphans ALTER COLUMN volume_name DROP DEFAULT"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE runner_volume_master_orphans ALTER COLUMN volume_name SET DEFAULT 'tuist-cache'"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE runner_volume_heads ALTER COLUMN volume_name SET DEFAULT 'tuist-cache'"

    alter table(:runner_cache_volume_measurements) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :retired, :boolean, default: false, null: false
    end

    alter table(:runner_cache_volume_uses) do
      add :superseded_at, :timestamptz
    end

    alter table(:runner_cache_volumes) do
      add :builtin_name, :text
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_cache_volumes, [:account_id, :builtin_name])
  end
end
