defmodule Tuist.Repo.Migrations.CreateQARuns do
  use Ecto.Migration

  def change do
    create table(:qa_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :app_build_id, references(:app_builds, type: :uuid, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :summary, :text

      timestamps(type: :timestamptz)
    end

    create index(:qa_runs, [:status])
    create index(:qa_runs, [:inserted_at])
    create index(:qa_runs, [:app_build_id])
  end
end
