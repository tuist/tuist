defmodule Tuist.Repo.Migrations.AddOriginAppInstallations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:origin_app_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :installation_id, :text, null: false
      add :app_id, :text, null: false
      add :namespace_id, :text, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:origin_app_installations, [:app_id, :installation_id],
             concurrently: true
           )

    create index(:origin_app_installations, [:account_id], concurrently: true)

    alter table(:vcs_connections) do
      # The UUID type stays unchanged; dropping NOT NULL does not rewrite the table.
      # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
      modify :github_app_installation_id, :uuid, null: true, from: {:uuid, null: false}

      add :origin_app_installation_id,
          references(:origin_app_installations, type: :uuid, on_delete: :delete_all)
    end

    create index(:vcs_connections, [:origin_app_installation_id], concurrently: true)

    # Install without a scan, then validate separately without blocking writes.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    create constraint(:vcs_connections, :vcs_connections_provider_installation,
             validate: false,
             check:
               "(provider = 0 AND github_app_installation_id IS NOT NULL AND origin_app_installation_id IS NULL) OR (provider = 1 AND origin_app_installation_id IS NOT NULL AND github_app_installation_id IS NULL)"
           )

    # Ecto has no helper for validating an existing check constraint.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    execute(&validate_provider_constraint/0, fn -> :ok end)
  end

  defp validate_provider_constraint do
    table =
      case prefix() do
        nil -> "vcs_connections"
        schema -> ~s("#{String.replace(schema, "\"", "\"\"")}".vcs_connections)
      end

    repo().query!(
      "ALTER TABLE #{table} VALIDATE CONSTRAINT vcs_connections_provider_installation"
    )
  end
end
