defmodule LuftServer.Repo.Migrations.CreateAISubscriptions do
  use Ecto.Migration

  # A person's Claude and ChatGPT subscriptions, keyed by their Tuist subject
  # (`sessions.user_sub`). Every credential column is encrypted by
  # `LuftServer.AISubscriptions.EncryptedBinary`.
  def change do
    create table(:ai_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_sub, :text, null: false
      add :provider, :text, null: false
      add :access_token, :binary
      add :refresh_token, :binary
      add :expires_at, :utc_datetime
      add :client_id, :text
      add :refreshing_until, :utc_datetime
      add :pending_login, :binary
      add :pending_expires_at, :utc_datetime
      add :next_poll_at, :utc_datetime

      timestamps()
    end

    create unique_index(:ai_subscriptions, [:user_sub, :provider])

    # Third-party sign-ins started in the current window, per key
    # (`LuftServer.SignInLimit`), to bound calls to OpenAI and MCP servers.
    create table(:sign_in_limits, primary_key: false) do
      add :key, :text, primary_key: true
      add :attempts, :integer, null: false
      add :window_started_at, :utc_datetime, null: false
    end
  end
end
