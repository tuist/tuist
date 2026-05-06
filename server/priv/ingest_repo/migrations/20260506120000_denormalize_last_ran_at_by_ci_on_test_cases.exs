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

  Backfill seeds the new columns from `test_case_runs` history so listings
  return the right set on day one. The insert sets `inserted_at = now64(6)`
  to ensure the backfill row outranks the pre-migration version under
  ReplacingMergeTree.
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

    # The `assumeNotNull(test_case_id)` cast is wrapped in its own inner
    # subquery so the outer `GROUP BY` sees a plain non-nullable column
    # already named `test_case_id`. Aliasing the cast at the outer level
    # would shadow the source column (ClickHouse resolves alias names ahead
    # of column names) and trip a "not under aggregate function" error.
    IngestRepo.query!("""
    INSERT INTO test_cases
      (id, name, module_name, suite_name, project_id, last_status, last_duration,
       last_ran_at, inserted_at, recent_durations, avg_duration, is_flaky,
       is_quarantined, last_run_id, state, last_ran_at_ci, last_ran_at_local)
    SELECT
      tc.id, tc.name, tc.module_name, tc.suite_name, tc.project_id,
      tc.last_status, tc.last_duration, tc.last_ran_at,
      now64(6) AS inserted_at,
      tc.recent_durations, tc.avg_duration, tc.is_flaky,
      tc.is_quarantined, tc.last_run_id, tc.state,
      ci_max.last_ran_at_ci,
      local_max.last_ran_at_local
    FROM (SELECT * FROM test_cases FINAL) AS tc
    LEFT JOIN (
      SELECT project_id, test_case_id, max(ran_at) AS last_ran_at_ci
      FROM (
        SELECT project_id, assumeNotNull(test_case_id) AS test_case_id, ran_at
        FROM test_case_runs
        WHERE is_ci AND isNotNull(test_case_id)
      )
      GROUP BY project_id, test_case_id
    ) AS ci_max
      ON tc.project_id = ci_max.project_id AND tc.id = ci_max.test_case_id
    LEFT JOIN (
      SELECT project_id, test_case_id, max(ran_at) AS last_ran_at_local
      FROM (
        SELECT project_id, assumeNotNull(test_case_id) AS test_case_id, ran_at
        FROM test_case_runs
        WHERE NOT is_ci AND isNotNull(test_case_id)
      )
      GROUP BY project_id, test_case_id
    ) AS local_max
      ON tc.project_id = local_max.project_id AND tc.id = local_max.test_case_id
    SETTINGS join_use_nulls = 1
    """)
  end

  def down do
    IngestRepo.query!("ALTER TABLE test_cases DROP COLUMN IF EXISTS last_ran_at_local")
    IngestRepo.query!("ALTER TABLE test_cases DROP COLUMN IF EXISTS last_ran_at_ci")
  end
end
