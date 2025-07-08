defmodule Tuist.Repo.Migrations.AddTestCaseRuns do
  use Ecto.Migration

  def change do
    create table(:test_case_runs) do
      add :identifier, :string, null: false
      add :module_hash, :string, null: false
      add :module_name, :string, null: false
      add :project_identifier, :string, null: false
      add :name, :string, null: false
      add :command_event_id, :integer, null: false
      add :status, :integer, null: false
      # credo:disable-for-next-line Credo.Checks.TimestampsType
      timestamps(updated_at: false)
    end

    create index(:test_case_runs, [:identifier, :command_event_id, :status])
  end
end
