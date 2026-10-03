defmodule Atlas.Repo.Migrations.CreateMissingSignalMessages do
  use Ecto.Migration

  def change do
    # Production applied the original signals migration before signal_messages
    # was added to that historical file, so this migration backfills the table.
    create_if_not_exists table(:signal_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :signal_id, references(:signals, type: :binary_id, on_delete: :delete_all), null: false
      add :author, :string
      add :body, :text, null: false
      add :source_url, :string
      add :source_timestamp, :utc_datetime

      timestamps()
    end

    create_if_not_exists index(:signal_messages, [:signal_id])
  end
end
