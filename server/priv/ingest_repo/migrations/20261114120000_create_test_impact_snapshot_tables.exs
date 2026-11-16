defmodule Tuist.IngestRepo.Migrations.CreateTestImpactSnapshotTables do
  @moduledoc """
  The test maps of coverage-based test selection
  (`Tuist.TestImpactAnalysis.Snapshots`), indexed in PostgreSQL by
  `test_impact_snapshots`:

  - `test_impact_snapshot_tests`: a snapshot's tests. A checkpoint holds
    every test of its run, numbered densely (`test_idx`) in module, suite
    and name order, so a module or a suite is a contiguous range. A test's
    name isn't stored: `test_case_id` identifies it, and `test_cases` names
    it where a skip list or an explanation needs it. An overlay
    holds only the tests that differ from its checkpoint, under the
    checkpoint's numbers (new tests continue after its last): a changed file
    set (`files_hash`, over the repository files the test and its suite's
    setup executed), the lines it ran in them (`lines_hash`) or status, and
    `stale` for a test that didn't run and whose files changed since the
    checkpoint.
  - `test_impact_snapshot_files`: the inverted index, one row per file,
    as roaring bitmaps of test numbers: `tests` executed it (in the test or
    its suite's setup), `suite_tests` are every test of the suites a test
    file belongs to, and `target_tests` every test of a module whose
    processes executed the file only outside its tests. An overlay's rows
    index only its own tests.
  - `test_impact_snapshot_lines`: the lines each test (`scope` `test`),
    suite's setup (`suite`) and module's processes outside its tests
    (`target`) ran in each file, as ranges `[first, last, first, last, …]`,
    empty when only the file is known: what coverage carry adds for a
    skipped test. `test_idx` is the test's number, or for a suite or a
    module the lowest number among its tests in the snapshot's numbering (an
    overlay's checkpoint's tests and its own). An overlay holds its own
    tests', and its suites' and modules' that ran.
  - `test_impact_run_decisions`: what each impact run's decision made of a
    snapshot's tests, one bitmap per decision and reason, in the numbering
    of `snapshot_id`; `evidence_snapshot_id` is the snapshot whose evidence
    decided them.

  Everything expires 31 days after the run that wrote it (`expires_at`),
  and decisions 31 days after the request.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_snapshot_tests
    (
      `project_id` Int64,
      `snapshot_id` UUID,
      `test_idx` UInt32 CODEC(Delta, ZSTD(1)),
      `test_case_id` UUID,
      `module_name` LowCardinality(String),
      `suite_name` String CODEC(ZSTD(3)),
      `status` Enum8('passed' = 1, 'failed' = 2, 'flaky' = 3, 'no_evidence' = 4, 'stale' = 5),
      `files_hash` UInt64,
      `lines_hash` UInt64,
      `expires_at` DateTime
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree")}
    ORDER BY (project_id, snapshot_id, test_idx)
    TTL expires_at
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_snapshot_files
    (
      `project_id` Int64,
      `snapshot_id` UUID,
      `path` String CODEC(ZSTD(3)),
      `is_test` Bool,
      `tests` AggregateFunction(groupBitmap, UInt32),
      `suite_tests` AggregateFunction(groupBitmap, UInt32),
      `target_tests` AggregateFunction(groupBitmap, UInt32),
      `expires_at` DateTime
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree")}
    ORDER BY (project_id, snapshot_id, path)
    TTL expires_at
    SETTINGS index_granularity = 1024
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_snapshot_lines
    (
      `project_id` Int64,
      `snapshot_id` UUID,
      `path` String CODEC(ZSTD(3)),
      `scope` Enum8('test' = 1, 'suite' = 2, 'target' = 3),
      `test_idx` UInt32 CODEC(Delta, ZSTD(1)),
      `line_ranges` Array(UInt32) CODEC(ZSTD(3)),
      `expires_at` DateTime
    )
    ENGINE = #{Migration.engine("MergeTree")}
    ORDER BY (project_id, snapshot_id, path, scope, test_idx)
    TTL expires_at
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_run_decisions
    (
      `project_id` Int64,
      `test_impact_run_id` UUID,
      `snapshot_id` UUID,
      `evidence_snapshot_id` UUID,
      `decision` Enum8('selected' = 1, 'skipped' = 2),
      `reason` LowCardinality(String),
      `tests` AggregateFunction(groupBitmap, UInt32),
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, test_impact_run_id, decision, reason, evidence_snapshot_id)
    TTL toDateTime(inserted_at) + INTERVAL 31 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_impact_run_decisions")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_impact_snapshot_lines")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_impact_snapshot_files")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_impact_snapshot_tests")
  end
end
