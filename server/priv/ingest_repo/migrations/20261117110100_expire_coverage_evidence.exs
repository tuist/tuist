defmodule Tuist.IngestRepo.Migrations.ExpireCoverageEvidence do
  @moduledoc """
  Keeps a run's per-test evidence in `coverage_files` (every `scope_kind` but
  `run`: `test`, `suite` and `target`) for two days after it was inserted
  (`Tuist.Tests.Coverage.Evidence.retention_days/0`), while the run's own
  rows keep `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90 by default). The
  evidence is only what a commit's fold builds the test maps from
  (`Tuist.TestImpactAnalysis.Snapshots`), seconds after the run reports;
  the maps keep what selection and carry need for 31 days at a fraction of
  the size. It requires the maps' backfill
  (`Tuist.TestImpactAnalysis.Workers.SnapshotBackfillWorker`) to have
  finished: older evidence is the only thing it builds from.

  The table's single time-to-live becomes two rules, a
  `DELETE WHERE scope_kind != 'run'` after two days and the file retention
  for every row. `MODIFY TTL` is metadata only, but ClickHouse follows it by
  default with one mutation rewriting every part of the table to apply the
  new rules, the table's whole retention at once. So it runs with
  `materialize_ttl_after_modify = 0`: parts written from now on carry the new
  rules and their merges drop the expired evidence. Existing parts would
  keep theirs until the old 90-day expiry recorded in them (merges that a
  part's expiry schedules go by what was recorded when it was written), so
  they are rewritten by one asynchronous `MATERIALIZE TTL` per monthly
  partition (`toYYYYMM(inserted_at)`), each unit of work one partition, as
  `Tuist.ClickHouse.IndexMaterialization` does for skip indexes, and with
  `mutations_sync = 0` the deploy doesn't wait for them.

  Rolling back restores the single time-to-live, again without rewriting
  existing parts. Evidence already deleted doesn't come back.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.Environment
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    files = Environment.coverage_retention_days().files

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE coverage_files
    MODIFY TTL toDateTime(inserted_at) + INTERVAL 2 DAY DELETE WHERE scope_kind != 'run',
      toDateTime(inserted_at) + INTERVAL #{files} DAY
    SETTINGS materialize_ttl_after_modify = 0
    """)

    flush()

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    IngestRepo
    |> IndexMaterialization.partition_ids(database, "coverage_files")
    |> Enum.map(
      &"ALTER TABLE coverage_files MATERIALIZE TTL IN PARTITION ID '#{String.replace(&1, "'", "\\'")}' SETTINGS mutations_sync = 0"
    )
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    |> Enum.each(&execute/1)
  end

  def down do
    files = Environment.coverage_retention_days().files

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE coverage_files
    MODIFY TTL toDateTime(inserted_at) + INTERVAL #{files} DAY
    SETTINGS materialize_ttl_after_modify = 0
    """)
  end
end
