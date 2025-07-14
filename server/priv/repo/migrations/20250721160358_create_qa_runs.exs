defmodule Tuist.Repo.Migrations.CreateQaRuns do
  use Ecto.Migration

  def change do
    create table(:qa_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :state, :string, null: false, default: "running"
      add :summary, :text
      add :app_build_id, references(:app_builds, on_delete: :delete_all, type: :uuid), null: false

      timestamps(type: :timestamptz)
    end

    create index(:qa_runs, [:app_build_id])
    create index(:qa_runs, [:state])
  end
end
