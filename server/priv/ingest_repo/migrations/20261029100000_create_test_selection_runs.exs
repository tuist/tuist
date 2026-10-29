defmodule Tuist.IngestRepo.Migrations.CreateTestSelectionRuns do
  @moduledoc """
  Coverage-based test selection (`Tuist.Tests.Selections`).

  A commit's test impact is what changed between it and its baseline (the
  nearest ancestor whose full run recorded per-test coverage evidence) and
  which tests that change reaches. It is deterministic for a
  `(head_sha, baseline_sha)` pair, so writing it again replaces it:

  - `test_impacts`: one row per pair, with its counts.
  - `test_impact_changed_files`: the changed paths and their status.
  - `test_impact_tests`: the tests the change reaches, with the reason and
    the changed path that matched.

  A test selection run is one invocation (a scheme or test plan on a
  destination, sharded or not) applying an impact to the tests it requested:

  - `test_selection_runs`: the invocation, its shard count, CI identity,
    counts and fallback reason. Linking the test run that reported its
    results writes the run again; merges keep the latest `updated_at`.
  - `test_selection_tests`: one row per requested test, selected (with the
    shard it is planned on) or skipped.

  Rows expire with the coverage evidence they were computed from,
  `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90 by default) after insertion.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_retention_days().files

    execute("""
    CREATE TABLE IF NOT EXISTS test_impacts
    (
      `project_id` Int64,
      `head_sha` String,
      `baseline_sha` String,
      `git_branch` String,
      `changed_files_count` UInt32,
      `impacted_tests_count` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, head_sha, baseline_sha)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_changed_files
    (
      `project_id` Int64,
      `head_sha` String,
      `baseline_sha` String,
      `path` String,
      `status` LowCardinality(String),
      `kind` LowCardinality(String),
      `impacted_tests_count` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, head_sha, baseline_sha, path)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_impact_tests
    (
      `project_id` Int64,
      `head_sha` String,
      `baseline_sha` String,
      `test_case_id` UUID,
      `module_name` String,
      `suite_name` String,
      `name` String,
      `reason` LowCardinality(String),
      `matched_path` String,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, head_sha, baseline_sha, test_case_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_selection_runs
    (
      `id` UUID,
      `project_id` Int64,
      `idempotency_key` String,
      `git_commit_sha` String,
      `git_branch` String,
      `baseline_sha` String,
      `scheme` String,
      `test_plan` String,
      `destination` String,
      `requested_targets` Array(String),
      `shard_count` UInt16,
      `shard_plan_id` Nullable(UUID),
      `test_run_id` Nullable(UUID),
      `ci_provider` LowCardinality(String),
      `ci_run_id` String,
      `ci_job_id` String,
      `requested_count` UInt32,
      `selected_count` UInt32,
      `skipped_count` UInt32,
      `skipped_duration` UInt64,
      `fallback_reason` LowCardinality(String),
      `inserted_at` DateTime64(6),
      `updated_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(updated_at)")}
    ORDER BY (project_id, id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_selection_tests
    (
      `project_id` Int64,
      `selection_run_id` UUID,
      `test_case_id` UUID,
      `module_name` String,
      `suite_name` String,
      `name` String,
      `decision` LowCardinality(String),
      `shard_index` UInt16,
      `reason` LowCardinality(String),
      `matched_path` String,
      `estimated_duration_ms` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("MergeTree")}
    ORDER BY (project_id, selection_run_id, decision, shard_index, test_case_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_selection_tests")
    execute("DROP TABLE IF EXISTS test_selection_runs")
    execute("DROP TABLE IF EXISTS test_impact_tests")
    execute("DROP TABLE IF EXISTS test_impact_changed_files")
    execute("DROP TABLE IF EXISTS test_impacts")
  end
end
