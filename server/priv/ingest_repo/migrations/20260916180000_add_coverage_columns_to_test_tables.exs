defmodule Tuist.IngestRepo.Migrations.AddCoverageColumnsToTestTables do
  @moduledoc """
  What coverage needs on the existing test tables. Adding a column is a
  metadata change in ClickHouse, whatever the table's size.

  `test_runs` gains the run's place in the repository's history: the base
  branch and merge base it was compared against, whether it ran for a pull
  request (and which), the repository's Git object format, and where the
  history came from (`history_source`: `client`, `provider`, `mixed` or
  `none`) with the reason anything is missing; `git_repository_id` names the
  repository the remote identified (`Tuist.GitHistory.Repository`, whose
  graph the run's commit belongs to) and `git_dirty` whether the checkout had
  uncommitted changes, in which case the run measured code that is not the
  commit's and stays at run level. `coverage_evidence_status` says whether it
  collected per-test evidence: `collected`, `not_linked` (asked for, but no
  test process recorded any, so no target links TestCoverageAttribution),
  `failed`, or empty when the run didn't ask.

  `execution_mode`, on `test_runs` and `test_module_runs`, is whether tests
  executed in parallel or serially, so the serial cost of per-test
  attribution can be weighed against history.

  `coverage_evidence` on `test_case_runs` is what the run's evidence holds for
  the test: `own` when it recorded the test's own evidence (a `test` scope in
  `coverage_files`), `overlapped` when it recorded the test only as
  overlapping another test of its process, and `none` otherwise. A test's
  newest evidence is then one read of its runs in key order, and a skipped
  test without evidence of its own can tell an overlap from a missing trait.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    ALTER TABLE test_runs
      ADD COLUMN IF NOT EXISTS base_branch String DEFAULT '',
      ADD COLUMN IF NOT EXISTS merge_base_sha String DEFAULT '',
      ADD COLUMN IF NOT EXISTS is_pull_request Bool DEFAULT false,
      ADD COLUMN IF NOT EXISTS pull_request_number UInt32 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS git_object_format LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS history_source LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS history_fallback_reason String DEFAULT '',
      ADD COLUMN IF NOT EXISTS git_repository_id Int64 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS git_dirty Bool DEFAULT false,
      ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS coverage_evidence_status LowCardinality(String) DEFAULT ''
    """)

    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT ''"
    )

    execute("""
    ALTER TABLE test_case_runs
    ADD COLUMN IF NOT EXISTS coverage_evidence Enum8('none' = 0, 'own' = 1, 'overlapped' = 2) DEFAULT 'none' CODEC(ZSTD(1))
    """)
  end

  def down do
    execute("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS coverage_evidence")
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS execution_mode")

    execute("""
    ALTER TABLE test_runs
      DROP COLUMN IF EXISTS base_branch,
      DROP COLUMN IF EXISTS merge_base_sha,
      DROP COLUMN IF EXISTS is_pull_request,
      DROP COLUMN IF EXISTS pull_request_number,
      DROP COLUMN IF EXISTS git_object_format,
      DROP COLUMN IF EXISTS history_source,
      DROP COLUMN IF EXISTS history_fallback_reason,
      DROP COLUMN IF EXISTS git_repository_id,
      DROP COLUMN IF EXISTS git_dirty,
      DROP COLUMN IF EXISTS execution_mode,
      DROP COLUMN IF EXISTS coverage_evidence_status
    """)
  end
end
