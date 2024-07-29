defmodule Tuist.Repo.DataMigrations.TestCaseRuns.MigratingSchema do
  use Ecto.Schema

  schema "test_case_runs" do
    field(:module_hash, :string)
    field(:status, Ecto.Enum, values: [success: 0, failure: 1])
    field(:flaky, :boolean, default: false)

    belongs_to(:command_event, Event)
    belongs_to(:test_case, TestCase)

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end
end

defmodule Tuist.Repo.Migrations.AddTestCasesTable do
  use Ecto.Migration
  alias Tuist.Repo.DataMigrations.TestCaseRuns.MigratingSchema

  def up do
    create table(:test_cases) do
      add :name, :string, null: false
      add :module_name, :string, null: false
      add :identifier, :string, null: false
      add :project_identifier, :string, null: false
      add :flaky, :boolean, default: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # credo:disable-for-next-line Credo.Checks.TimestampsType
      timestamps(updated_at: false)
    end

    create unique_index(:test_cases, [:identifier])
    create index(:test_case_runs, [:identifier, :status, :module_hash])

    Tuist.Repo.delete_all(MigratingSchema)

    alter table(:test_case_runs) do
      remove :identifier
      remove :name
      remove :module_name
      remove :project_identifier
      add :test_case_id, references(:test_cases, on_delete: :delete_all), null: false
    end
  end

  def down do
    drop unique_index(:test_cases, [:identifier])

    alter table(:test_case_runs) do
      remove :test_case_id
      add :name, :string, null: false
      add :identifier, :string, null: true
      add :module_name, :string, null: true
      add :project_identifier, :string, null: true
    end

    drop table(:test_cases)
  end
end
