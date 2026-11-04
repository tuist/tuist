defmodule Tuist.IngestRepo.Migrations.CreateTestImpactTables do
  @moduledoc """
  The tables of coverage-based test selection (`Tuist.TestImpactAnalysis`):

  - `test_impact_diffs`: the files that changed between a baseline and the
    commit that was checked out, as the client's diff listed them, each with
    the test modules it can affect. A diff is deterministic, so one row per
    checked-out commit and baseline serves every invocation on that commit, and
    identical concurrent writes collapse.
  - `test_impact_runs`: one row per `tuist test` invocation that asked for a
    selection: the diff it used, the baseline's runs it read its tests from
    (so every shard's skip list matches the decision), its scope, the outcome
    and why, the trace of the rules that decided it, and the counts. Fallbacks
    are recorded too. Ordered for the overview's date-range read; the run page
    finds a run by id through the bloom filter.
  - `test_impact_run_tests`: the tests a run selected, with the rule that
    selected each one, ordered so a run's tests, or a shard's suites, are one
    prefix read. Skipped tests are never stored: they are derived.

  Diffs and selected tests are built from file-level evidence and expire with
  it, `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90 by default) after insertion.
  Runs keep the overview's statistics as long as the coverage run totals,
  `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365 by default).

  The tuples are positional, since the `ch` driver drops element names from
  the types it inserts with: a changed file is `(path, status, blob,
  affected_modules)` and a rule trace entry `(rule, selected, skipped,
  verdict)`.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_retention_days()

    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_diffs
    (
      `project_id` Int64,
      `commit_sha` String,
      `baseline_sha` String,
      `changed_files` Array(Tuple(String, LowCardinality(String), String, Array(String))) CODEC(ZSTD(1)),
      `changed_files_count` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree")}
    ORDER BY (project_id, commit_sha, baseline_sha)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_runs
    (
      `project_id` Int64,
      `id` UUID,
      `inserted_at` DateTime64(6),
      `head_sha` String,
      `commit_sha` String,
      `baseline_sha` Nullable(String),
      `baseline_run_ids` Array(UUID),
      `git_branch` String,
      `dirty` Bool,
      `strategy` LowCardinality(String),
      `build_system` LowCardinality(String),
      `platform` LowCardinality(String),
      `build_context` Map(LowCardinality(String), String),
      `requested_modules` Array(LowCardinality(String)),
      `outcome` LowCardinality(String),
      `reason` LowCardinality(String),
      `matched_path` String,
      `rules_version` LowCardinality(String),
      `rule_trace` Array(Tuple(LowCardinality(String), UInt32, UInt32, LowCardinality(String))),
      `requested_count` UInt32,
      `skipped_count` UInt32,
      `selected_count` UInt32,
      INDEX idx_id id TYPE bloom_filter GRANULARITY 4
    )
    ENGINE = #{Migration.engine("MergeTree")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, inserted_at, id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.runs} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_run_tests
    (
      `test_impact_run_id` UUID,
      `project_id` Int64,
      `test_case_id` UUID,
      `module_name` String,
      `suite_name` String,
      `name` String,
      `reason` LowCardinality(String),
      `matched_path` String,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("MergeTree")}
    ORDER BY (project_id, test_impact_run_id, module_name, suite_name, name)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_impact_run_tests")
    execute("DROP TABLE IF EXISTS test_impact_runs")
    execute("DROP TABLE IF EXISTS test_impact_diffs")
  end
end
