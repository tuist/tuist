defmodule Tuist.Repo.Migrations.CreateQAScreenshots do
  use Ecto.Migration

  def up do
    create table(:qa_screenshots, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :qa_run_id, references(:qa_runs, type: :uuid, on_delete: :delete_all), null: false

      add :qa_step_id, references(:qa_steps, type: :uuid, on_delete: :delete_all), null: true

      add :file_name, :string, null: false
      add :title, :string, null: false

      timestamps(type: :timestamptz)
    end

    create index(:qa_screenshots, [:qa_run_id])
    create index(:qa_screenshots, [:qa_step_id])
    create index(:qa_screenshots, [:inserted_at])
    create unique_index(:qa_screenshots, [:qa_run_id, :file_name])
  end

  def down do
    drop table(:qa_screenshots)
  end
end
