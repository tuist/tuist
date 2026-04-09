defmodule Tuist.IngestRepo.Migrations.AddLastRunIdToTestCases do
  @moduledoc """
  Adds `last_run_id` (UUID) to the `test_cases` table so that the quarantined
  and test-case listing pages can read it directly instead of joining
  `test_case_runs` to compute `argMax(test_run_id, ran_at)`.

  Before this change, the quarantined test cases query joined ALL test_case_runs
  for a project (182–190 M rows read, p50 ≈ 4.4 s) just to get the last run ID.
  With `last_run_id` denormalized, the join is eliminated entirely.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS last_run_id UUID DEFAULT '00000000-0000-0000-0000-000000000000'
    """)
  end

  def down do
    IngestRepo.query!("""
    ALTER TABLE test_cases
    DROP COLUMN IF EXISTS last_run_id
    """)
  end
end
