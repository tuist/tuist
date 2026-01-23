defmodule Tuist.Repo.Migrations.CreateTestCaseEvents do
  use Ecto.Migration

  def change do
    create table(:test_case_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :test_case_id, :uuid, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :actor_type, :string, null: false
      add :actor_id, references(:accounts, on_delete: :nilify_all)
      add :reason, :text
      add :metadata, :map, default: %{}

      timestamps(type: :timestamptz)
    end

    create index(:test_case_events, [:test_case_id])
    create index(:test_case_events, [:project_id])
    create index(:test_case_events, [:test_case_id, :inserted_at])
  end
end
