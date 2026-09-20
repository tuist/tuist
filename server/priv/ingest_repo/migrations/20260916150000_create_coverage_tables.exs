defmodule Tuist.IngestRepo.Migrations.CreateCoverageTables do
  @moduledoc """
  The build-system-neutral `coverage_files` and `coverage_runs`, which take
  over from `xcode_coverage_files` and `xcode_coverage_runs`.

  The Xcode tables held early access data only, so nothing is copied: the new
  tables start empty and coverage accumulates from the first run reported
  after the release. The old tables are left untouched and nothing reads or
  writes them; a later migration drops them. What the new tables add:

  - `build_system`, `coverage_tool` and `coverage_tool_version`, so JaCoCo and
    LCOV reports land in the same tables and every row says what produced it;
  - `scope_kind` and `scope_id`: whose coverage a row is (`run` today; a
    `target`, `suite` or `test` once per-test attribution exists), part of the
    sort key so a shard's rows for one scope replace each other;
  - `evidence_kind`: `observed` (measured in this run), `cached` (a build
    system reused a test result whose inputs were identical) or `carried`
    (reused from an earlier run on proof the covered files did not change);
  - `in_repository`: whether the path is repository-relative and Git knows it,
    the only files evidence may later rely on;
  - `git_object_format`, so SHA-1 and SHA-256 repositories never mix;
  - `scheme`, the configuration a run's totals belong to;
  - `git_commit_sha` on both, so a commit's coverage (the union of its runs)
    and the evidence at an ancestor are read without a join through
    `test_runs`;
  - branch counters (`covered_branches`, `total_branches`, per-line
    `branch_*` arrays) that `xccov` never fills but JaCoCo and LCOV do;
  - time-to-live: file detail expires after `TUIST_COVERAGE_FILE_RETENTION_DAYS`
    (90 by default) and run totals after `TUIST_COVERAGE_RUN_RETENTION_DAYS`
    (365 by default).

  Coverage is a property of a commit: `coverage_commits` holds the totals of
  each measured commit over the union of its runs, with the measured set
  (which schemes, each full or partial, and which runs) and whether the
  measurement is complete, versioned like `coverage_runs` and retained like
  it. `git_commit_files` is the commit's file listing (path and blob per file,
  keyed by repository and commit), what coverage is measured against and where
  tracked files and ancestor blobs are read; it expires with the file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_retention_days()

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_files
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `build_system` LowCardinality(String) DEFAULT 'xcode',
      `shard_index` UInt32 DEFAULT 0,
      `partial` Bool DEFAULT false,
      `scope_kind` LowCardinality(String) DEFAULT 'run',
      `scope_id` String DEFAULT '',
      `evidence_kind` LowCardinality(String) DEFAULT 'observed',
      `path` String,
      `in_repository` Bool DEFAULT true,
      `git_blob_id` String,
      `targets` Array(LowCardinality(String)),
      `is_test` Bool DEFAULT false,
      `git_commit_sha` String DEFAULT '',
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `execution_counts` Array(UInt64) CODEC(ZSTD(1)),
      `covered_branches` UInt32 DEFAULT 0,
      `total_branches` UInt32 DEFAULT 0,
      `branch_line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `branch_covered` Array(UInt32) CODEC(ZSTD(1)),
      `branch_total` Array(UInt32) CODEC(ZSTD(1)),
      `function_names` Array(String),
      `function_line_numbers` Array(UInt32),
      `function_execution_counts` Array(UInt64),
      `function_covered_lines` Array(UInt32),
      `function_executable_lines` Array(UInt32),
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, shard_index, scope_kind, scope_id, path)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_runs
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `build_system` LowCardinality(String) DEFAULT 'xcode',
      `coverage_tool` LowCardinality(String) DEFAULT '',
      `coverage_tool_version` LowCardinality(String) DEFAULT '',
      `git_object_format` LowCardinality(String) DEFAULT '',
      `scheme` String DEFAULT '',
      `git_commit_sha` String DEFAULT '',
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `partial` Bool DEFAULT false,
      `version` UInt64,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(version)")}
    ORDER BY (project_id, test_run_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.runs} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS coverage_commits
    (
      `project_id` Int64,
      `git_commit_sha` String,
      `git_repository_id` Int64 DEFAULT 0,
      `build_system` LowCardinality(String) DEFAULT 'xcode',
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `measured_files_count` UInt32 DEFAULT 0,
      `unmeasured_files_count` UInt32 DEFAULT 0,
      `schemes` Array(String),
      `partial_schemes` Array(String),
      `test_run_ids` Array(UUID),
      `complete` Bool DEFAULT false,
      `completeness` LowCardinality(String) DEFAULT '',
      `version` UInt64,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(version)")}
    ORDER BY (project_id, git_commit_sha)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.runs} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS git_commit_files
    (
      `repository_id` Int64,
      `sha` String,
      `path` String,
      `git_blob_id` String DEFAULT '',
      `mode` UInt32 DEFAULT 0,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (repository_id, sha, path)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS git_commit_files")
    execute("DROP TABLE IF EXISTS coverage_commits")
    execute("DROP TABLE IF EXISTS coverage_runs")
    execute("DROP TABLE IF EXISTS coverage_files")
  end
end
