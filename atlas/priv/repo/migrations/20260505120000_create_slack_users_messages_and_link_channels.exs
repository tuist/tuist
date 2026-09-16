defmodule Atlas.Repo.Migrations.CreateSlackUsersMessagesAndLinkChannels do
  use Ecto.Migration

  def change do
    alter table(:slack_channels) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:slack_channels, [:account_id])

    create table(:slack_users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :slack_integration_id,
          references(:slack_integrations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slack_user_id, :string, null: false
      add :name, :string
      add :real_name, :string
      add :display_name, :string
      add :avatar_url, :string
      add :is_bot, :boolean, default: false, null: false
      add :is_external, :boolean, default: false, null: false
      add :last_synced_at, :utc_datetime

      timestamps()
    end

    create unique_index(:slack_users, [:slack_integration_id, :slack_user_id])

    create table(:slack_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :slack_channel_id,
          references(:slack_channels, type: :binary_id, on_delete: :delete_all), null: false

      add :slack_user_id, references(:slack_users, type: :binary_id, on_delete: :nilify_all)

      add :account_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :slack_ts, :string, null: false
      add :thread_ts, :string
      add :text, :text
      add :permalink, :string
      add :posted_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:slack_messages, [:slack_channel_id, :slack_ts])
    create index(:slack_messages, [:slack_channel_id, :thread_ts])
    create index(:slack_messages, [:account_event_id])
  end
end
