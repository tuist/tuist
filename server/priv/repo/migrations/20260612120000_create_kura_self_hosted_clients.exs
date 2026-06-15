defmodule Tuist.Repo.Migrations.CreateKuraSelfHostedClients do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:kura_self_hosted_clients, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :client_id, :string, null: false
      add :encrypted_secret_hash, :string, null: false
      add :name, :string, null: false
      add :last_used_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:kura_self_hosted_clients, [:client_id])
    create unique_index(:kura_self_hosted_clients, [:account_id, :name])
    create index(:kura_self_hosted_clients, [:account_id])
  end
end
