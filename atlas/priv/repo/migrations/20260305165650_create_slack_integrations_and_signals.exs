defmodule Atlas.Repo.Migrations.CreateSlackIntegrationsAndSignals do
  use Ecto.Migration

  def change do
    create table(:slack_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :bot_token, :string, null: false

      timestamps()
    end

    create table(:slack_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, :string, null: false
      add :channel_name, :string, null: false
      add :slack_integration_id, references(:slack_integrations, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:slack_channels, [:channel_id, :slack_integration_id])

    create table(:signals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text
      add :source, :string, null: false
      add :source_url, :string
      add :source_author, :string
      add :source_channel, :string
      add :source_timestamp, :utc_datetime

      timestamps()
    end

    create index(:signals, [:source])
    create index(:signals, [:inserted_at])

    create table(:signal_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :signal_id, references(:signals, type: :binary_id, on_delete: :delete_all), null: false
      add :author, :string
      add :body, :text, null: false
      add :source_url, :string
      add :source_timestamp, :utc_datetime

      timestamps()
    end

    create index(:signal_messages, [:signal_id])
  end
end
