defmodule Tuist.IngestRepo.Migrations.CreateCoverageTables do
  @moduledoc """
  Replaces `xcode_coverage_files` and `xcode_coverage_runs` with the
  build-system-neutral `coverage_files` and `coverage_runs`.

  The Xcode tables were early access only, so the rows are copied over in one
  `INSERT ... SELECT` and the old tables dropped. What the new tables add:

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
  - branch counters (`covered_branches`, `total_branches`, per-line
    `branch_*` arrays) that `xccov` never fills but JaCoCo and LCOV do;
  - time-to-live: file detail expires after `TUIST_COVERAGE_FILE_RETENTION_DAYS`
    (90 by default) and run totals after `TUIST_COVERAGE_RUN_RETENTION_DAYS`
    (365 by default).
  """
  use Ecto.Migration

  alias Tuist.Environment

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
    ENGINE = ReplacingMergeTree(inserted_at)
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
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `partial` Bool DEFAULT false,
      `version` UInt64,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(version)
    ORDER BY (project_id, test_run_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.runs} DAY
    """)

    if table_exists?("xcode_coverage_files") do
      # A blob id is 40 hex digits in a SHA-1 repository and 64 in a SHA-256 one.
      execute("""
      INSERT INTO coverage_files
      (id, test_run_id, project_id, build_system, shard_index, partial, path, in_repository, git_blob_id, targets, is_test,
       covered_lines, executable_lines, line_numbers, execution_counts, function_names, function_line_numbers,
       function_execution_counts, function_covered_lines, function_executable_lines, inserted_at)
      SELECT id, test_run_id, project_id, 'xcode', shard_index, partial, path,
             git_blob_id != '' AND NOT startsWith(path, '/'), git_blob_id, targets, is_test,
             covered_lines, executable_lines, line_numbers, execution_counts, function_names, function_line_numbers,
             function_execution_counts, function_covered_lines, function_executable_lines, inserted_at
      FROM xcode_coverage_files
      """)

      execute("""
      INSERT INTO coverage_runs
      (project_id, test_run_id, build_system, coverage_tool, coverage_tool_version, git_object_format, scheme,
       covered_lines, executable_lines, partial, version, inserted_at)
      SELECT r.project_id, r.test_run_id, 'xcode', 'xccov', t.xcode_version,
             multiIf(f.blob_length = 64, 'sha256', f.blob_length = 40, 'sha1', ''), t.scheme,
             r.covered_lines, r.executable_lines, r.partial, r.version, r.inserted_at
      FROM xcode_coverage_runs AS r
      LEFT JOIN (SELECT id AS run_id, any(xcode_version) AS xcode_version, any(scheme) AS scheme FROM test_runs GROUP BY id) AS t
        ON t.run_id = r.test_run_id
      LEFT JOIN (SELECT test_run_id AS run_id, max(length(git_blob_id)) AS blob_length FROM xcode_coverage_files GROUP BY test_run_id) AS f
        ON f.run_id = r.test_run_id
      """)

      execute("DROP TABLE xcode_coverage_runs")
      execute("DROP TABLE xcode_coverage_files")
    end
  end

  def down do
    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_files
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `shard_index` UInt32 DEFAULT 0,
      `partial` Bool DEFAULT false,
      `path` String,
      `git_blob_id` String,
      `targets` Array(LowCardinality(String)),
      `is_test` Bool DEFAULT false,
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `execution_counts` Array(UInt64) CODEC(ZSTD(1)),
      `function_names` Array(String),
      `function_line_numbers` Array(UInt32),
      `function_execution_counts` Array(UInt64),
      `function_covered_lines` Array(UInt32),
      `function_executable_lines` Array(UInt32),
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, test_run_id, shard_index, path)
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS xcode_coverage_runs
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `covered_lines` UInt64,
      `executable_lines` UInt64,
      `partial` Bool DEFAULT false,
      `version` UInt64,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = ReplacingMergeTree(version)
    ORDER BY (project_id, test_run_id)
    """)

    execute("""
    INSERT INTO xcode_coverage_files
    (id, test_run_id, project_id, shard_index, partial, path, git_blob_id, targets, is_test, covered_lines,
     executable_lines, line_numbers, execution_counts, function_names, function_line_numbers,
     function_execution_counts, function_covered_lines, function_executable_lines, inserted_at)
    SELECT id, test_run_id, project_id, shard_index, partial, path, git_blob_id, targets, is_test, covered_lines,
           executable_lines, line_numbers, execution_counts, function_names, function_line_numbers,
           function_execution_counts, function_covered_lines, function_executable_lines, inserted_at
    FROM coverage_files
    WHERE build_system = 'xcode' AND scope_kind = 'run'
    """)

    execute("""
    INSERT INTO xcode_coverage_runs (project_id, test_run_id, covered_lines, executable_lines, partial, version, inserted_at)
    SELECT project_id, test_run_id, covered_lines, executable_lines, partial, version, inserted_at
    FROM coverage_runs
    WHERE build_system = 'xcode'
    """)

    execute("DROP TABLE coverage_runs")
    execute("DROP TABLE coverage_files")
  end

  defp table_exists?(table_name) do
    {:ok, %{rows: [[count]]}} =
      Tuist.IngestRepo.query(
        "SELECT count() FROM system.tables WHERE database = currentDatabase() AND name = {table:String}",
        %{table: table_name}
      )

    count > 0
  end
end
