defmodule Tuist.IngestRepo.Migrations.ShortenCoverageTargetSourcesRetention do
  @moduledoc """
  Keeps `coverage_target_sources` (`Tuist.Tests.Coverage.TargetSources`) for
  31 days after insertion instead of `TUIST_COVERAGE_FILE_RETENTION_DAYS`
  (90 by default). A source points at a run whose evidence coverage carry
  now reads from the test maps (`Tuist.TestImpactAnalysis.Snapshots`), which
  are kept 31 days, and each fold that finds the source again writes it
  anew, so an older row has nothing left to carry from.

  As for `coverage_files`' evidence
  (`20261117110100_expire_coverage_evidence`), the time-to-live changes
  with `materialize_ttl_after_modify = 0` and existing parts are rewritten
  by one asynchronous `MATERIALIZE TTL` per partition (`mutations_sync = 0`).
  The table has no partition key, so its one partition is the whole table:
  a row per repository, target and selective-testing hash, small next to
  `coverage_files`. Rolling back restores the file retention without
  rewriting existing parts; rows already deleted don't come back.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.Environment
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE coverage_target_sources
    MODIFY TTL toDateTime(inserted_at) + INTERVAL 31 DAY
    SETTINGS materialize_ttl_after_modify = 0
    """)

    flush()

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    IngestRepo
    |> IndexMaterialization.partition_ids(database, "coverage_target_sources")
    |> Enum.map(
      &"ALTER TABLE coverage_target_sources MATERIALIZE TTL IN PARTITION ID '#{String.replace(&1, "'", "\\'")}' SETTINGS mutations_sync = 0"
    )
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    |> Enum.each(&execute/1)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE coverage_target_sources
    MODIFY TTL toDateTime(inserted_at) + INTERVAL #{Environment.coverage_retention_days().files} DAY
    SETTINGS materialize_ttl_after_modify = 0
    """)
  end
end
