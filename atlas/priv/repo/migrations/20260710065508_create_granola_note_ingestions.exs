defmodule Atlas.Repo.Migrations.CreateGranolaNoteIngestions do
  use Ecto.Migration

  def change do
    create table(:granola_note_ingestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_id, :string, null: false
      add :note_updated_at, :utc_datetime
      add :status, :string, null: false
      add :ignore_reason, :string

      add :account_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:granola_note_ingestions, [:external_id])
    create index(:granola_note_ingestions, [:status])
    create index(:granola_note_ingestions, [:account_event_id])
  end
end
