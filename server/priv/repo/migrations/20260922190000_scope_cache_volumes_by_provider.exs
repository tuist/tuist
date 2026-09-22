defmodule Tuist.Repo.Migrations.ScopeCacheVolumesByProvider do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # PostgreSQL 16 adds constant defaults without rewriting existing rows.
    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :provider, :text, null: false, default: "github"

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :provider_instance, :text, null: false, default: "github.com"
      add :scope_id, :text

      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :repository_id, :bigint, null: true
    end

    flush()

    # Backfill only this unreleased feature table; retain UUIDs and physical storage.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "UPDATE #{table_name()} SET scope_id = repository_id::text WHERE scope_id IS NULL"

    create unique_index(
             :runner_cache_volumes,
             [:account_id, :provider, :provider_instance, :scope_id, :key, :architecture, :uid],
             name: :runner_cache_volumes_provider_identity,
             concurrently: true
           )

    drop index(:runner_cache_volumes, [:account_id, :repository_id, :key, :architecture, :uid],
           name: :runner_cache_volumes_identity,
           concurrently: true
         )
  end

  def down do
    # Provider identities cannot be represented by the previous GitHub-only schema.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM #{table_name()} WHERE provider <> 'github') THEN
        RAISE EXCEPTION 'Remove non-GitHub cache volumes after storage cleanup before rolling back';
      END IF;
    END $$
    """

    create unique_index(
             :runner_cache_volumes,
             [:account_id, :repository_id, :key, :architecture, :uid],
             name: :runner_cache_volumes_identity,
             concurrently: true
           )

    drop index(
           :runner_cache_volumes,
           [:account_id, :provider, :provider_instance, :scope_id, :key, :architecture, :uid],
           name: :runner_cache_volumes_provider_identity,
           concurrently: true
         )

    alter table(:runner_cache_volumes) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :scope_id

      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :provider_instance

      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :provider

      # excellent_migrations:safety-assured-for-next-line not_null_added column_type_changed
      modify :repository_id, :bigint, null: false
    end
  end

  defp table_name do
    schema = String.replace(prefix() || "public", ~s("), ~s(""))
    ~s("#{schema}"."runner_cache_volumes")
  end
end
