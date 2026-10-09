defmodule Tuist.IngestRepo.Migrations.CreateCoverageTargetSources do
  @moduledoc """
  Where a test target's coverage can be carried from, by the
  selective-testing hash it ran with (`Tuist.Tests.Coverage.TargetSources`):
  a row per clean run that executed the target whole, passed it and recorded
  its evidence. The same hash is the same target over the same inputs, so a
  commit whose run skipped the target finds its source in one read, without
  walking its history, the way selective testing finds the hit. The latest
  run per hash is the one read. Rows expire with the evidence they point to,
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
    CREATE TABLE IF NOT EXISTS coverage_target_sources
    (
      `project_id` Int64,
      `target` String,
      `selective_testing_hash` String,
      `test_run_id` UUID,
      `git_commit_sha` String,
      `git_repository_id` Int64,
      `ran_at` DateTime64(6),
      `inserted_at` DateTime64(6)
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(ran_at)")}
    ORDER BY (project_id, target, selective_testing_hash, test_run_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS coverage_target_sources")
  end
end
