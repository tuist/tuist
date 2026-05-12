defmodule Tuist.Repo.Migrations.AddWebhookEndpointsTable do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :string, null: false
      add :signing_secret, :binary, null: false

      timestamps(type: :timestamptz)
    end

    create index(:webhook_endpoints, [:account_id])
  end
end
