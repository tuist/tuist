defmodule Tuist.IngestRepo.Migrations.CreateCoverageTables do
  @moduledoc """
  The coverage tables: the build-system-neutral `coverage_files` and
  `coverage_runs`, which take over from `xcode_coverage_files` and
  `xcode_coverage_runs`, and the commit listings, changed files and
  enumerated tests coverage is measured against.

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

  Coverage is a property of a commit: its totals over the union of its runs
  live in PostgreSQL (`coverage_commits`, beside the commit graph), since
  they outlive the detail kept here. `git_commit_files` is the commit's file
  listing (path and blob per file, keyed by repository and commit), what
  coverage is measured against and where tracked files and ancestor blobs are
  read; it expires with the file detail.

  `test_run_changed_files` holds the files a run changed between the merge
  base and the head, with the line ranges of their hunks and the blob each
  had at the head, so patch coverage can be computed against the run's own
  coverage rows.

  `test_run_enumerated_tests` holds the tests a run could have executed, as
  the client listed them without running any (`xcodebuild -enumerate-tests`).
  A run's filters do not narrow the list, so it is the candidate set a
  selective run chose from: what says which tests a run left out. Keyed by
  the test case's stable id, the one `test_case_runs` carries, so "enumerated
  and not run" is a difference of two sets. `function_name` is the function
  of a test whose results report it under a display name (Swift Testing's
  `@Test("…")`): the enumeration lists the function and the result bundle the
  display name, so this is what lets a skipped test take the display name an
  earlier run recorded; it is looked up within the project, which the sort
  key does not reach, hence the bloom filter.

  `coverage_runs` is ordered by project and run, but a commit's coverage is
  read through its runs, found by SHA: run ids are time-ordered, so a
  commit's runs sit in few granules and a bloom filter on the SHA skips the
  rest. All three expire with the file detail but `coverage_runs`.
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
      `inserted_at` DateTime64(6) DEFAULT now(),
      INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 1
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(version)")}
    ORDER BY (project_id, test_run_id)
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

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_changed_files
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `path` String,
      `previous_path` String DEFAULT '',
      `status` LowCardinality(String),
      `git_blob_id` String DEFAULT '',
      `hunk_starts` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `hunk_ends` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `truncated` Bool DEFAULT false,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, path)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_enumerated_tests
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `test_case_id` UUID,
      `module_name` String,
      `suite_name` String DEFAULT '',
      `name` String,
      `function_name` String DEFAULT '',
      `enabled` Bool DEFAULT true,
      `inserted_at` DateTime64(6) DEFAULT now(),
      INDEX idx_function_name function_name TYPE bloom_filter GRANULARITY 4
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, test_case_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_run_enumerated_tests")
    execute("DROP TABLE IF EXISTS test_run_changed_files")
    execute("DROP TABLE IF EXISTS git_commit_files")
    execute("DROP TABLE IF EXISTS coverage_runs")
    execute("DROP TABLE IF EXISTS coverage_files")
  end
end
