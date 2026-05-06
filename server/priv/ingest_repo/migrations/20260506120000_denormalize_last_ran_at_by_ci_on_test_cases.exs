defmodule Tuist.IngestRepo.Migrations.DenormalizeLastRanAtByCiOnTestCases do
  @moduledoc """
  Adds `last_ran_at_ci` and `last_ran_at_local` to `test_cases` so the Test
  Cases listing's CI/Local-filtered active-period lookup can resolve its
  active set with a direct `WHERE last_ran_at_ci BETWEEN ?` instead of
  joining `test_case_runs` (production traces showed the join scanning
  ~94 M rows / ~3.94 GB for one project).

  The Elixir write path in `Tuist.Tests.create_test_cases/4` already does a
  read-modify-write per (project_id, id), merging fields like `is_flaky`,
  `state`, and `recent_durations` from the previously-known row before
  inserting a new ReplacingMergeTree version. The new columns slot into the
  same merge: when the current `Test` is `is_ci`, the row's
  `last_ran_at_ci` is set from `data.ran_at` and `last_ran_at_local` is
  carried forward from the existing row (and vice versa).

  Backfill copies `last_ran_at` into both new columns. This deliberately
  ignores the actual CI-vs-local origin of each historical run, so the
  CI/Local toggle is briefly imprecise for stale tests right after deploy
  — a test whose last run was local will show up in the CI listing
  (and vice versa) until its next CI/local run rewrites the matching
  column. For projects that use test insights actively, both columns
  converge to the correct values within a day or two of normal traffic.
  Inactive tests will continue to show the seeded fallback indefinitely;
  this is acceptable because they're inactive.

  The alternative — joining `test_case_runs` per (project_id, test_case_id,
  is_ci) to compute the true historical max — would be precise but adds
  a multi-way LEFT JOIN over the per-execution table for a one-time cost
  the active-traffic path will overwrite anyway.

  The insert sets `inserted_at = now64(6)` so the backfill row outranks
  the pre-migration version under ReplacingMergeTree.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS last_ran_at_ci Nullable(DateTime64(6)) DEFAULT NULL
    """)

    IngestRepo.query!("""
    ALTER TABLE test_cases
    ADD COLUMN IF NOT EXISTS last_ran_at_local Nullable(DateTime64(6)) DEFAULT NULL
    """)

    IngestRepo.query!("""
    INSERT INTO test_cases
      (id, name, module_name, suite_name, project_id, last_status, last_duration,
       last_ran_at, inserted_at, recent_durations, avg_duration, is_flaky,
       is_quarantined, last_run_id, state, last_ran_at_ci, last_ran_at_local)
    SELECT
      id, name, module_name, suite_name, project_id,
      last_status, last_duration, last_ran_at,
      now64(6) AS inserted_at,
      recent_durations, avg_duration, is_flaky,
      is_quarantined, last_run_id, state,
      last_ran_at AS last_ran_at_ci,
      last_ran_at AS last_ran_at_local
    FROM test_cases FINAL
    """)
  end

  def down do
    IngestRepo.query!("ALTER TABLE test_cases DROP COLUMN IF EXISTS last_ran_at_local")
    IngestRepo.query!("ALTER TABLE test_cases DROP COLUMN IF EXISTS last_ran_at_ci")
  end
end
