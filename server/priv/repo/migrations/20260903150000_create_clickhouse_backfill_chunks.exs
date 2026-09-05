defmodule Tuist.Repo.Migrations.CreateClickhouseBackfillChunks do
  @moduledoc """
  Progress ledger for the ClickHouse backfill (spec #73).

  The copy is `INSERT ... SELECT`, which is not idempotent: re-running a chunk
  against a `MergeTree` table duplicates its rows, and a `ReplacingMergeTree`
  only collapses them on a merge that may not have happened yet. So a chunk
  that has been copied has to be recorded as copied somewhere durable, and
  Postgres is the only store in the system that is neither the source nor the
  destination of the copy.

  Lives in Postgres rather than ClickHouse for that reason: a ledger inside
  the destination would be lost by exactly the failure that makes resuming
  necessary.
  """

  use Ecto.Migration

  def up do
    create table(:clickhouse_backfill_chunks) do
      add :table_name, :string, null: false
      # Half-open interval, so adjacent chunks cannot double count a row that
      # sits exactly on a boundary.
      add :chunk_start, :timestamptz, null: false
      add :chunk_end, :timestamptz, null: false
      add :status, :string, null: false, default: "pending"
      add :source_rows, :bigint
      add :destination_rows, :bigint
      add :error, :text
      add :started_at, :timestamptz
      add :finished_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The resume cursor. A chunk is identified by its table and interval, so a
    # re-run finds the completed ones and skips them.
    #
    # Built non-concurrently because the table is created empty in this same
    # migration: there are no rows to scan and no readers to block, which is
    # the situation the concurrent form exists for.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:clickhouse_backfill_chunks, [:table_name, :chunk_start, :chunk_end])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:clickhouse_backfill_chunks, [:status])
  end

  def down do
    # Dropping is the whole rollback: this table is created by this migration
    # and holds only the backfill's own progress, so nothing outside the
    # migration reads it and there is no customer data to lose.
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:clickhouse_backfill_chunks)
  end
end
