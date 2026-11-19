defmodule LuftServer.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # SHA-256 of the cookie's session token; the token itself is never stored.
      add :token_hash, :binary, null: false
      # The Tuist user's ID (the ID token's `sub`) and what the ID token said about them.
      add :user_sub, :string, null: false
      add :email, :string
      add :handle, :string
      # Tuist's tokens, encrypted with a key derived from SECRET_KEY_BASE.
      add :access_token, :binary, null: false
      add :refresh_token, :binary, null: false
      add :access_token_expires_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:expires_at])
  end
end
