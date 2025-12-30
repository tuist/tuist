defmodule Tuist.Repo.Migrations.DropTestCasesTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:test_case_runs)
    drop_if_exists table(:test_cases)
  end

  def down do
    create table(:test_cases) do
      add :name, :string
      add :module_name, :string
      add :identifier, :text
      add :project_identifier, :string
      add :project_id, references(:projects, on_delete: :delete_all)
      add :flaky, :boolean, default: false
      timestamps(type: :timestamptz)
    end

    create index(:test_cases, [:project_id])
    create unique_index(:test_cases, [:identifier])

    create table(:test_case_runs) do
      add :status, :integer
      add :flaky, :boolean, default: false
      add :command_event_id, :binary_id
      add :test_case_id, references(:test_cases, on_delete: :delete_all)
      add :xcode_target_id, :binary_id
      timestamps(type: :timestamptz, updated_at: false)
    end

    create index(:test_case_runs, [:test_case_id])
    create index(:test_case_runs, [:flaky])

    create index(:test_case_runs, [:flaky],
             where: "flaky = true",
             name: :test_case_runs_flaky_only_index
           )

    create index(:test_case_runs, [:status])
  end
end
