defmodule Atlas.Repo.Migrations.CreateUserConnections do
  use Ecto.Migration

  def change do
    create table(:user_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_user_id, :string, null: false
      add :account_name, :string, null: false
      add :workspace_id, :string
      add :access_token, :binary, null: false
      add :refresh_token, :binary
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime
      add :needs_authorization, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_connections, [:user_id, :provider])

    create table(:user_connection_authorizations, primary_key: false) do
      add :nonce_hash, :binary, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create index(:user_connection_authorizations, [:expires_at])
    create index(:user_connection_authorizations, [:user_id])
  end
end
