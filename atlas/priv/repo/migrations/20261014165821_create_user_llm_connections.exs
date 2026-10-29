defmodule Atlas.Repo.Migrations.CreateUserLlmConnections do
  use Ecto.Migration

  def change do
    create table(:user_llm_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :text, null: false
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :timestamptz
      add :pending_login, :binary
      add :pending_expires_at, :timestamptz
      add :next_poll_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:user_llm_connections, [:user_id, :provider])

    create constraint(:user_llm_connections, :supported_provider,
             check: "provider IN ('claude', 'chatgpt')"
           )
  end
end
