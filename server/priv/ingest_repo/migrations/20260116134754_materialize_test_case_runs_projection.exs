defmodule Tuist.IngestRepo.Migrations.MaterializeTestCaseRunsProjection do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_test_case_id"
  end

  def down do
    :ok
  end
end
