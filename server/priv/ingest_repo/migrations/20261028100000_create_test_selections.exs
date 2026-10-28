defmodule Tuist.IngestRepo.Migrations.CreateTestSelections do
  @moduledoc """
  Coverage-based test selection plans (`Tuist.Tests.Selections`), one per
  commit: which tests or test targets a run of that commit had to execute
  and which it could skip, against the nearest full run's per-test coverage
  evidence (the baseline).

  - `test_selections`: the plan of a commit. Planning a commit again
    replaces its plan; merges keep the latest.
  - `test_selection_decisions`: one row per test (`scope_kind` `test`) or
    test target (`scope_kind` `target`) the plan decided on, with the files
    its baseline evidence says it executed and the changed ones among them.
  - `test_selection_changed_files`: the files that changed between the
    baseline and the planned commit.

  Rows expire with the coverage evidence they were planned from,
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
    CREATE TABLE IF NOT EXISTS test_selections
    (
      `id` UUID,
      `project_id` Int64,
      `git_commit_sha` String,
      `git_branch` String,
      `scope` LowCardinality(String),
      `mode` LowCardinality(String),
      `baseline_commit_sha` String,
      `fallback_reason` LowCardinality(String),
      `selected_count` UInt32,
      `skipped_count` UInt32,
      `changed_files_count` UInt32,
      `skipped_duration` UInt64,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, git_commit_sha)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_selection_decisions
    (
      `id` UUID,
      `test_selection_id` UUID,
      `project_id` Int64,
      `scheme` String,
      `scope_kind` LowCardinality(String),
      `module_name` String,
      `suite_name` String,
      `name` String,
      `test_case_id` Nullable(UUID),
      `source_path` String,
      `decision` LowCardinality(String),
      `reason` LowCardinality(String),
      `covered_paths` Array(String) CODEC(ZSTD(1)),
      `changed_paths` Array(String),
      `evidence_test_run_id` Nullable(UUID),
      `duration` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("MergeTree")}
    ORDER BY (project_id, test_selection_id, module_name, suite_name, name, scheme)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_selection_changed_files
    (
      `test_selection_id` UUID,
      `project_id` Int64,
      `path` String,
      `status` LowCardinality(String),
      `kind` LowCardinality(String),
      `selected_count` UInt32,
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("MergeTree")}
    ORDER BY (project_id, test_selection_id, path)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_selection_changed_files")
    execute("DROP TABLE IF EXISTS test_selection_decisions")
    execute("DROP TABLE IF EXISTS test_selections")
  end
end
