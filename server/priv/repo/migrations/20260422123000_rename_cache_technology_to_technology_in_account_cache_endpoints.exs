defmodule Tuist.Repo.Migrations.RenameCacheTechnologyToTechnologyInAccountCacheEndpoints do
  use Ecto.Migration

  def up do
    drop_old_index()
    rename_column("cache_technology", "technology")
    create_new_index()
  end

  def down do
    drop_new_index()
    rename_column("technology", "cache_technology")
    create_old_index()
  end

  defp rename_column(from, to) do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'account_cache_endpoints'
          AND column_name = '#{from}'
      ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'account_cache_endpoints'
          AND column_name = '#{to}'
      ) THEN
        ALTER TABLE account_cache_endpoints RENAME COLUMN #{from} TO #{to};
      END IF;
    END
    $$;
    """)
  end

  defp drop_old_index do
    execute("DROP INDEX IF EXISTS account_cache_endpoints_account_id_cache_technology_url_index")
  end

  defp drop_new_index do
    execute("DROP INDEX IF EXISTS account_cache_endpoints_account_id_technology_url_index")
  end

  defp create_new_index do
    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS account_cache_endpoints_account_id_technology_url_index
    ON account_cache_endpoints (account_id, technology, url)
    """)
  end

  defp create_old_index do
    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS account_cache_endpoints_account_id_cache_technology_url_index
    ON account_cache_endpoints (account_id, cache_technology, url)
    """)
  end
end
