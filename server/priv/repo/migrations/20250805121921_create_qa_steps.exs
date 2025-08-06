defmodule Tuist.Repo.Migrations.CreateQASteps do
  use Ecto.Migration

  def change do
    create table(:qa_steps, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :qa_run_id, references(:qa_runs, type: :uuid, on_delete: :delete_all), null: false
      add :summary, :text, null: false
      add :description, :text, null: false
      add :issues, {:array, :string}, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    create index(:qa_steps, [:qa_run_id])
    create index(:qa_steps, [:inserted_at])
  end
end
