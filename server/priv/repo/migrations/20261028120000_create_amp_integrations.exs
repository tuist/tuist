defmodule Tuist.Repo.Migrations.CreateAmpIntegrations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:amp_integrations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :provider_token, :binary
      add :token_fingerprint, :string
      add :enabled, :boolean, null: false, default: true
      add :status, :string, null: false, default: "pending"
      add :revision, :integer, null: false, default: 1
      add :last_checked_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:amp_integrations, [:account_id], concurrently: true)
    create unique_index(:amp_integrations, [:token_fingerprint], concurrently: true)

    alter table(:sandboxes) do
      add :amp_integration_id, references(:amp_integrations, type: :uuid, on_delete: :nilify_all)
    end

    create index(:sandboxes, [:amp_integration_id], concurrently: true)
  end
end
