defmodule Tuist.IngestRepo.Migrations.CreateTestRunSelections do
  @moduledoc """
  `test_run_selections`: how many tests each test run's selection avoided,
  the measure of test selection effectiveness on the dashboards
  (`Tuist.Tests.RunSelections`). One row per test run that selected:

  - `scope_tests`: the tests in scope, those that ran plus those avoided;
  - `avoided_tests`: the tests the selection skipped, and `avoided_by` the
    same per reason (`module_hash`, `coverage`; other build systems add their
    own);
  - `estimated_tests`: how many of the avoided tests were estimated from a
    module's earlier run rather than counted in the run that stored the hash
    it was skipped with;
  - the run's build system, CI flag, scheme and branch, copied for the
    dashboards' filters, and the impact run it shares with its shards.

  A row is computed again whenever more of the run arrives, so the latest
  computation (`inserted_at`) is kept. Partitioned by month of the run, like
  the run itself, and kept as long as the runs are.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_run_selections
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `ran_at` DateTime64(6),
      `build_system` LowCardinality(String),
      `is_ci` Bool,
      `scheme` String,
      `git_branch` String,
      `strategy` LowCardinality(String),
      `test_impact_run_id` Nullable(UUID),
      `scope_tests` UInt32,
      `avoided_tests` UInt32,
      `estimated_tests` UInt32,
      `avoided_by` Map(LowCardinality(String), UInt32),
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(ran_at)
    ORDER BY (project_id, test_run_id)
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_run_selections")
  end
end
