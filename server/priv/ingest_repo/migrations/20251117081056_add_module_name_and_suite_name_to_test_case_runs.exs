defmodule Tuist.IngestRepo.Migrations.AddModuleNameAndSuiteNameToTestCaseRuns do
  use Ecto.Migration

  def up do
    alter table(:test_case_runs) do
      add :module_name, :string, default: ""
      add :suite_name, :string, default: ""
    end

    # Add indices for the new columns
    execute("ALTER TABLE test_case_runs ADD INDEX idx_module_name (module_name) TYPE bloom_filter GRANULARITY 4")
    execute("ALTER TABLE test_case_runs ADD INDEX idx_suite_name (suite_name) TYPE bloom_filter GRANULARITY 4")
  end

  def down do
    alter table(:test_case_runs) do
      remove :module_name
      remove :suite_name
    end
  end
end
