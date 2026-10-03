defmodule Atlas.Repo.Migrations.DropSlackIntegrations do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:slack_users, [:slack_integration_id, :slack_user_id])

    alter table(:slack_users) do
      remove :slack_integration_id
    end

    create unique_index(:slack_users, [:slack_user_id])

    drop_if_exists unique_index(:slack_channels, [:channel_id, :slack_integration_id])

    alter table(:slack_channels) do
      remove :slack_integration_id
    end

    create unique_index(:slack_channels, [:channel_id])

    drop table(:slack_integrations)
  end

  def down do
    create table(:slack_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :bot_token, :bytea
      add :signing_secret, :bytea

      timestamps()
    end

    drop_if_exists unique_index(:slack_channels, [:channel_id])

    alter table(:slack_channels) do
      add :slack_integration_id,
          references(:slack_integrations, type: :binary_id, on_delete: :delete_all)
    end

    create unique_index(:slack_channels, [:channel_id, :slack_integration_id])

    drop_if_exists unique_index(:slack_users, [:slack_user_id])

    alter table(:slack_users) do
      add :slack_integration_id,
          references(:slack_integrations, type: :binary_id, on_delete: :delete_all)
    end

    create unique_index(:slack_users, [:slack_integration_id, :slack_user_id])
  end
end
