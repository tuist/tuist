defmodule Atlas.Repo.Migrations.DropSignalTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:signal_summaries)
    drop_if_exists table(:signal_messages)
    drop_if_exists table(:signals)
  end

  def down do
    create table(:signals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text
      add :source, :string, null: false
      add :source_url, :string
      add :source_author, :string
      add :source_channel, :string
      add :source_timestamp, :utc_datetime
      add :status, :string, null: false, default: "new"

      timestamps()
    end

    create index(:signals, [:source])
    create index(:signals, [:inserted_at])
    create index(:signals, [:status])

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

    create table(:signal_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :signal_id, references(:signals, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:signal_summaries, [:signal_id])
  end
end
