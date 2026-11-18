defmodule Tuist.IngestRepo.Migrations.CreateCoverageRunFiles do
  @moduledoc """
  Splits a run's per-file coverage (the `run` rows of `coverage_files`) into
  what the run measured and the file version it measured:

  - `coverage_run_files`: one row per file per shard report, with the
    report's counts, the per-line execution counts aligned to the layout's
    lines (empty when no line ran), the functions' calls and covered lines,
    and the layout it names (`layout_id`, and `epoch`, which is derived from
    the path and the insertion day rather than stored). It drops what every row of
    a file version repeated (`git_blob_id`, `line_numbers`, the function
    names, lines and sizes), the unused `id`, and the scope columns, which
    were always `run`. Branch counters, which no client sends, aren't kept.
  - `coverage_file_layouts`: each file version once per project and week
    (`epoch`, the first day of the week of the reports that name it; each
    path starts its weeks on its own weekday, so the first report of a day
    rewrites about a seventh of a project's versions, not all of them):
    path, blob, executable lines and functions.

  Of a run row's bytes, 59–77% were the file version's, repeated by every run
  and shard: at 100,000 files a run's rows take 4–7 times less.

  Run rows are partitioned by day and dropped whole once their newest row
  expired (`ttl_only_drop_parts`), so expiry never rewrites parts. Layouts
  are partitioned by the day their week starts and expire `TUIST_COVERAGE_FILE_RETENTION_DAYS`
  plus eight days after their week starts, after every run row of the week.

  Existing run rows are copied by
  `Tuist.Tests.Coverage.Workers.RunFilesBackfillWorker`, which the
  PostgreSQL migration of the same release queues; `coverage_files` keeps
  the per-test evidence, and its old run rows expire with the file
  retention.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    days = Environment.coverage_retention_days().files

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS coverage_run_files
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `shard_index` UInt32 DEFAULT 0,
      `path` String CODEC(ZSTD(1)),
      `epoch` Date ALIAS toDate(inserted_at, 'UTC') - ((toUInt32(toDate(inserted_at, 'UTC')) - CRC32(path) % 7) % 7),
      `layout_id` UInt32,
      `build_system` LowCardinality(String) DEFAULT 'xcode',
      `partial` Bool DEFAULT false,
      `in_repository` Bool DEFAULT true,
      `is_test` Bool DEFAULT false,
      `targets` Array(LowCardinality(String)) CODEC(ZSTD(1)),
      `git_commit_sha` String DEFAULT '' CODEC(ZSTD(1)),
      `covered_lines` UInt32,
      `executable_lines` UInt32,
      `execution_counts` Array(UInt32) CODEC(T64, ZSTD(1)),
      `function_execution_counts` Array(UInt32) CODEC(T64, ZSTD(1)),
      `function_covered_lines` Array(UInt32) CODEC(T64, ZSTD(1)),
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toDate(inserted_at)
    ORDER BY (project_id, test_run_id, shard_index, path)
    TTL toDateTime(inserted_at) + INTERVAL #{days} DAY
    SETTINGS ttl_only_drop_parts = 1
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS coverage_file_layouts
    (
      `project_id` Int64,
      `epoch` Date,
      `path` String CODEC(ZSTD(1)),
      `layout_id` UInt32,
      `git_blob_id` String DEFAULT '' CODEC(ZSTD(1)),
      `line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `function_names` Array(String) CODEC(ZSTD(1)),
      `function_line_numbers` Array(UInt32) CODEC(Delta, ZSTD(1)),
      `function_executable_lines` Array(UInt32) CODEC(ZSTD(1))
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree")}
    PARTITION BY epoch
    ORDER BY (project_id, epoch, path, layout_id)
    TTL epoch + INTERVAL #{days + 8} DAY
    SETTINGS ttl_only_drop_parts = 1
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS coverage_file_layouts")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS coverage_run_files")
  end
end
