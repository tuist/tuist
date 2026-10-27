defmodule Tuist.IngestRepo.Migrations.ReplayBuildRunsIntoVersionedTable do
  @moduledoc """
  Replays the pre-swap `build_runs` into the versioned table created by the
  previous migration.

  That migration copied a snapshot and then exchanged the tables, so rows
  written to the old table in between never reached the new one. They can't be
  selected on time: `ProcessBuildWorker` carries `inserted_at` over from the
  placeholder, so a processed row written during the copy can carry a timestamp
  from days earlier, and `mark_failed_build_processing/4` only runs after five
  attempts with backoff. Filtering on `inserted_at` would skip exactly the
  processed rows this whole change is about, so the replay reads the old table
  whole.

  The version expression is the same deterministic one the copy used, so every
  row it already wrote is replayed as an identical duplicate and collapses on
  merge. Until those merges run, reads that go through `FINAL` (the build list)
  are unaffected while raw `count()` analytics see the duplicates.

  Separate from the swap so that a failure here re-runs only this, which is a
  plain `INSERT ... SELECT` and safe to repeat.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @version "if(status = 'processing', inserted_at, addSeconds(inserted_at, 1))"

  def up do
    if table_exists?("build_runs_new") do
      columns = column_names("build_runs_new")

      IngestRepo.query!(
        """
        INSERT INTO build_runs (#{columns}, updated_at)
        SELECT #{columns}, #{@version}
        FROM build_runs_new
        """,
        [],
        timeout: 1_200_000
      )

      Logger.info("Replayed build_runs_new into build_runs")
    else
      Logger.info("build_runs_new is gone; nothing to replay")
    end
  end

  def down do
    :ok
  end

  defp table_exists?(table_name) do
    {:ok, %{rows: [[count]]}} =
      IngestRepo.query(
        """
        SELECT count()
        FROM system.tables
        WHERE database = currentDatabase() AND name = {table:String}
        """,
        %{table: table_name}
      )

    count > 0
  end

  defp column_names(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name
        FROM system.columns
        WHERE database = currentDatabase() AND table = {table:String}
        ORDER BY position
        """,
        %{table: table_name}
      )

    Enum.map_join(rows, ", ", fn [name] -> name end)
  end
end
