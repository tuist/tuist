defmodule Atlas.Repo.Migrations.AddSlackAppToChannelsAndUsers do
  use Ecto.Migration

  def up do
    alter table(:slack_channels) do
      add :slack_app, :string, null: false, default: "company"
    end

    drop_if_exists unique_index(:slack_channels, [:channel_id])
    create unique_index(:slack_channels, [:slack_app, :channel_id])

    alter table(:slack_users) do
      add :slack_app, :string, null: false, default: "company"
    end

    drop_if_exists unique_index(:slack_users, [:slack_user_id])
    create unique_index(:slack_users, [:slack_app, :slack_user_id])
  end

  def down do
    drop_if_exists unique_index(:slack_users, [:slack_app, :slack_user_id])
    create unique_index(:slack_users, [:slack_user_id])

    alter table(:slack_users) do
      remove :slack_app
    end

    drop_if_exists unique_index(:slack_channels, [:slack_app, :channel_id])
    create unique_index(:slack_channels, [:channel_id])

    alter table(:slack_channels) do
      remove :slack_app
    end
  end
end
