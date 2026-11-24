defmodule Tuist.IngestRepo.Migrations.ShortenCoverageFileRetention do
  @moduledoc """
  Applies the file retention's new default, 31 days instead of 90
  (`TUIST_COVERAGE_FILE_RETENTION_DAYS`, `Tuist.Environment.coverage_retention_days/1`),
  to the tables that keep it: the run rows of `coverage_files` (its evidence
  keeps its two days) and `test_impact_diffs`. An install that sets the
  variable keeps the days it set. A commit's totals and per-file figures
  (`coverage_commits`, `coverage_file_deltas`) keep their own retention, so
  only line-level detail of older commits goes: what a file's page and the
  raw-row reads show.

  As in `ExpireCoverageEvidence`, `MODIFY TTL` runs without materializing,
  so the deploy doesn't wait for a rewrite of every part, and existing parts
  take the new rules through one asynchronous `MATERIALIZE TTL` per
  partition.

  Rolling back restores the 90 days, again without rewriting existing parts.
  Rows already deleted don't come back.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Tests.Coverage.Evidence

  @disable_ddl_transaction true
  @disable_migration_lock true

  @tables ["coverage_files", "test_impact_diffs"]

  def up do
    days = Environment.coverage_retention_days().files

    for table <- @tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute(
        "ALTER TABLE #{table} MODIFY TTL #{ttl(table, days)} SETTINGS materialize_ttl_after_modify = 0"
      )
    end

    flush()

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    for table <- @tables,
        partition <- IndexMaterialization.partition_ids(IngestRepo, database, table) do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute(
        "ALTER TABLE #{table} MATERIALIZE TTL IN PARTITION ID '#{String.replace(partition, "'", "\\'")}' SETTINGS mutations_sync = 0"
      )
    end
  end

  def down do
    days =
      Environment.coverage_retention_days(%{
        "TUIST_COVERAGE_FILE_RETENTION_DAYS" => previous_days()
      }).files

    for table <- @tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute(
        "ALTER TABLE #{table} MODIFY TTL #{ttl(table, days)} SETTINGS materialize_ttl_after_modify = 0"
      )
    end
  end

  defp previous_days, do: System.get_env("TUIST_COVERAGE_FILE_RETENTION_DAYS") || "90"

  defp ttl("coverage_files", days) do
    "toDateTime(inserted_at) + INTERVAL #{Evidence.retention_days()} DAY DELETE WHERE scope_kind != 'run', " <>
      "toDateTime(inserted_at) + INTERVAL #{days} DAY"
  end

  defp ttl(_table, days), do: "toDateTime(inserted_at) + INTERVAL #{days} DAY"
end
