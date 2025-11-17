defmodule Tuist.IngestRepo.Migrations.AddTestStatsToTestModuleRuns do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_module_runs ADD COLUMN test_suite_count Int32 DEFAULT 0")
    execute("ALTER TABLE test_module_runs ADD COLUMN test_case_count Int32 DEFAULT 0")
    execute("ALTER TABLE test_module_runs ADD COLUMN avg_test_case_duration Int32 DEFAULT 0")
  end

  def down do
    execute("ALTER TABLE test_module_runs DROP COLUMN test_suite_count")
    execute("ALTER TABLE test_module_runs DROP COLUMN test_case_count")
    execute("ALTER TABLE test_module_runs DROP COLUMN avg_test_case_duration")
  end
end
