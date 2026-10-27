defmodule Tuist.Repo.Migrations.DropClickhouseBackfillChunks do
  @moduledoc """
  Drops the progress ledger of the copy onto the in-cluster ClickHouse
  (spec #73). The in-cluster server is the system of record and the copy
  tooling is gone, so nothing reads or writes the table.
  """

  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop_if_exists table(:clickhouse_backfill_chunks)
  end

  def down, do: :ok
end
