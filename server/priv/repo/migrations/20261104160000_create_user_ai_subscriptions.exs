defmodule Tuist.Repo.Migrations.CreateUserAiSubscriptions do
  use Ecto.Migration

  def change do
    create table(:user_ai_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :timestamptz
      add :pending_login, :binary
      add :pending_expires_at, :timestamptz
      add :next_poll_at, :timestamptz
      add :refreshing_until, :timestamptz
      add :client_id, :string

      timestamps(type: :timestamptz)
    end

    # The table is created empty in the same transaction; no existing
    # readers or writers can be blocked while its index is built.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_ai_subscriptions, [:user_id, :provider])
  end
end
