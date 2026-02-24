defmodule Tuist.IngestRepo.Migrations.BackfillNullProjectIdAndRanAtInTestCaseRuns do
  @moduledoc """
  Backfills `project_id` and `ran_at` for test_case_runs rows where these columns
  are NULL. These columns were added as Nullable in a previous migration but are
  always populated for new data. The ~290k legacy rows with NULLs are backfilled
  by joining against `test_runs` to retrieve the real values.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO test_case_runs
    SELECT
      tcr.id,
      tcr.name,
      tcr.test_run_id,
      tcr.test_module_run_id,
      tcr.test_suite_run_id,
      tcr.test_case_id,
      tr.project_id,
      tcr.is_ci,
      tcr.scheme,
      tcr.account_id,
      tr.ran_at,
      tcr.git_branch,
      tcr.git_commit_sha,
      tcr.status,
      tcr.is_flaky,
      tcr.is_new,
      tcr.duration,
      tcr.inserted_at,
      tcr.module_name,
      tcr.suite_name
    FROM test_case_runs AS tcr
    INNER JOIN test_runs AS tr ON tcr.test_run_id = tr.id
    WHERE tcr.project_id IS NULL OR tcr.ran_at IS NULL
    """
  end

  def down do
    :ok
  end
end
