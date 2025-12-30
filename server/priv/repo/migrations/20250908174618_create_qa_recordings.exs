defmodule Tuist.Repo.Migrations.CreateQaRecordings do
  use Ecto.Migration

  def change do
    create table(:qa_recordings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :qa_run_id, references(:qa_runs, on_delete: :delete_all, type: :uuid), null: false
      add :started_at, :timestamptz, null: false
      add :duration, :integer, null: false

      timestamps(type: :timestamptz)
    end
  end
end
