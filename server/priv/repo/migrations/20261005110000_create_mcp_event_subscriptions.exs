defmodule Tuist.Repo.Migrations.CreateMcpEventSubscriptions do
  use Ecto.Migration

  def change do
    create table(:mcp_event_subscriptions, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :account_token_id, references(:account_tokens, type: :uuid, on_delete: :delete_all)
      add :oauth_client_id, :uuid

      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all)
      add :event_name, :string, null: false
      add :callback_url, :binary, null: false
      add :signing_secret, :binary, null: false
      add :refresh_before, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:mcp_event_subscriptions, [:project_id, :event_name])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:mcp_event_subscriptions, [:account_id, :event_name])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:mcp_event_subscriptions, [:user_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:mcp_event_subscriptions, [:refresh_before])

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:mcp_event_subscriptions, :one_credential,
             check: "(account_token_id IS NOT NULL) <> (oauth_client_id IS NOT NULL)"
           )
  end
end
