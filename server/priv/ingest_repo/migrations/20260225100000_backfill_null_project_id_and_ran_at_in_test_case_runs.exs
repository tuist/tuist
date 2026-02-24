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
    INSERT INTO test_case_runs (
      id, name, test_run_id, test_module_run_id, test_suite_run_id,
      status, duration, module_name, suite_name, inserted_at,
      project_id, is_ci, scheme, account_id, ran_at,
      git_branch, test_case_id, git_commit_sha, is_flaky, is_new
    )
    SELECT
      tcr.id,
      tcr.name,
      tcr.test_run_id,
      tcr.test_module_run_id,
      tcr.test_suite_run_id,
      tcr.status,
      tcr.duration,
      tcr.module_name,
      tcr.suite_name,
      tcr.inserted_at,
      tr.project_id,
      tcr.is_ci,
      tcr.scheme,
      tcr.account_id,
      tr.ran_at,
      tcr.git_branch,
      tcr.test_case_id,
      tcr.git_commit_sha,
      tcr.is_flaky,
      tcr.is_new
    FROM test_case_runs AS tcr
    INNER JOIN test_runs AS tr ON tcr.test_run_id = tr.id
    WHERE tcr.project_id IS NULL OR tcr.ran_at IS NULL
    """
  end

  def down do
    :ok
  end
end
