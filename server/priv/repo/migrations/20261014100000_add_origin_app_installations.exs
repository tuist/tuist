defmodule Tuist.Repo.Migrations.AddOriginAppInstallations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create table(:origin_app_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :installation_id, :text, null: false
      add :namespace_id, :text, null: false
      add :namespace_slug, :text, null: false
      add :scopes, {:array, :text}, default: [], null: false
      add :suspended, :boolean, default: false, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:origin_app_installations, [:account_id], concurrently: true)
    create unique_index(:origin_app_installations, [:installation_id], concurrently: true)
    create unique_index(:origin_app_installations, [:namespace_id], concurrently: true)

    alter table(:vcs_connections) do
      # The UUID type is unchanged; only NOT NULL is removed, with no table rewrite.
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :github_app_installation_id, :uuid, null: true, from: {:uuid, null: false}

      add :origin_app_installation_id,
          references(:origin_app_installations, type: :uuid, on_delete: :delete_all)

      add :origin_repository_id, :text
    end

    create index(:vcs_connections, [:origin_app_installation_id], concurrently: true)

    # Install without scanning under an exclusive lock, then validate separately.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:vcs_connections, :vcs_connection_provider_installation,
             validate: false,
             check:
               "(provider = 0 AND github_app_installation_id IS NOT NULL AND origin_app_installation_id IS NULL) OR " <>
                 "(provider = 1 AND origin_app_installation_id IS NOT NULL AND origin_repository_id IS NOT NULL AND github_app_installation_id IS NULL)"
           )

    # Validation uses a weaker lock and leaves normal writes available.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE vcs_connections VALIDATE CONSTRAINT vcs_connection_provider_installation"
  end

  def down do
    # One atomic statement locks out new installs before checking for customer data.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      LOCK TABLE origin_app_installations IN ACCESS EXCLUSIVE MODE;
      IF EXISTS (SELECT 1 FROM origin_app_installations) THEN
        RAISE EXCEPTION 'Disconnect Origin installations before rolling back this migration';
      END IF;
      ALTER TABLE vcs_connections
        DROP CONSTRAINT vcs_connection_provider_installation,
        DROP COLUMN origin_repository_id,
        DROP COLUMN origin_app_installation_id,
        ALTER COLUMN github_app_installation_id SET NOT NULL;
      DROP TABLE origin_app_installations;
    END $$;
    """
  end
end
