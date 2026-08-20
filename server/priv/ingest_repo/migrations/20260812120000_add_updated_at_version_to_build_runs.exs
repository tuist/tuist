defmodule Tuist.IngestRepo.Migrations.AddUpdatedAtVersionToBuildRuns do
  @moduledoc """
  Gives `build_runs` a dedicated ReplacingMergeTree version column.

  The table was `ReplacingMergeTree(inserted_at)`, so `inserted_at` was both
  the build's user-visible timestamp and the dedup version. `ProcessBuildWorker`
  builds the processed row from the existing `processing` row, carrying its
  `inserted_at` over, so the replacement was inserted with the *same version*
  as the placeholder it was meant to supersede. On merge the engine picks an
  arbitrary survivor, and the placeholder can win — leaving a build stuck at
  `status = 'processing'`, `duration = 0` forever. The tie also defeats the
  read path, where duplicates are resolved with `ORDER BY inserted_at DESC
  LIMIT 1`.

  `updated_at` splits the two roles: `inserted_at` stays the build's timestamp
  and the partition key, `updated_at` advances on every write. Same shape as
  `runner_jobs`, which is `ReplacingMergeTree(updated_at)` partitioned by
  `enqueued_at`.

  The engine's version column can't be changed in place, hence the table swap.
  The copy derives `updated_at` so that any non-terminal placeholder loses to
  its replacement: rows still holding `status = 'processing'` keep
  `inserted_at` as their version while every other row is bumped a second past
  it. That repairs, in one pass, every stuck pair whose two rows have not been
  merged away yet.

  Rows written to the old table between the copy and the exchange are replayed
  by the migration that follows this one; they cannot be selected on time here
  because a replacement carries the placeholder's `inserted_at`, which says
  nothing about when the row was written.

  Columns, skipping indexes and projections are all reconstructed from
  `system.*` so the copy is a faithful reproduction of whatever the instance
  actually has; hardcoding any of them here drops the rest on the floor.

  The old table is left behind as `build_runs_new` — the replay reads from it,
  and it makes the swap reversible. A follow-up migration drops it once the new
  table has been verified, the same sequence used by the previous `build_runs`
  swap.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Deterministic, so the replay that follows produces byte-identical rows for
  # everything this copy already wrote.
  @version "if(status = 'processing', inserted_at, addSeconds(inserted_at, 1))"

  def up do
    if version_column_present?() do
      # A failure anywhere after `EXCHANGE TABLES` leaves the migration marked
      # as failed with the swap already done, so a re-run must not rebuild the
      # table from what is now the swapped-in copy.
      Logger.info("build_runs already dedups on updated_at; leaving it as is")
    else
      swap_in_versioned_table()
    end
  end

  def down do
    :ok
  end

  defp swap_in_versioned_table do
    IngestRepo.query!("DROP TABLE IF EXISTS build_runs_new")

    columns = column_names("build_runs")
    column_definitions = column_definitions("build_runs")
    indexes = index_definitions("build_runs")
    projections = projection_definitions("build_runs")

    IngestRepo.query!("""
    CREATE TABLE build_runs_new (
      #{column_definitions},
      updated_at DateTime64(6) DEFAULT inserted_at#{if indexes != "", do: ",\n  #{indexes}", else: ""}#{if projections != "", do: ",\n  #{projections}", else: ""}
    ) ENGINE = ReplacingMergeTree(updated_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, id)
    SETTINGS deduplicate_merge_projection_mode = 'rebuild'
    """)

    IngestRepo.query!(
      """
      INSERT INTO build_runs_new (#{columns}, updated_at)
      SELECT #{columns}, #{@version}
      FROM build_runs
      """,
      [],
      timeout: 1_200_000
    )

    IngestRepo.query!("EXCHANGE TABLES build_runs AND build_runs_new")

    Logger.info("build_runs now dedups on updated_at; previous table kept as build_runs_new")
  end

  defp version_column_present? do
    {:ok, %{rows: [[count]]}} =
      IngestRepo.query("""
      SELECT count()
      FROM system.columns
      WHERE database = currentDatabase() AND table = 'build_runs' AND name = 'updated_at'
      """)

    count > 0
  end

  defp column_names(table_name) do
    table_name
    |> columns()
    |> Enum.map_join(", ", fn [name, _type, _default_kind, _default_expression] -> name end)
  end

  defp column_definitions(table_name) do
    table_name
    |> columns()
    |> Enum.map_join(",\n  ", fn [name, type, default_kind, default_expression] ->
      default_clause =
        case default_kind do
          "DEFAULT" -> " DEFAULT #{default_expression}"
          _ -> ""
        end

      "#{name} #{type}#{default_clause}"
    end)
  end

  defp columns(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name, type, default_kind, default_expression
        FROM system.columns
        WHERE database = currentDatabase() AND table = {table:String}
        ORDER BY position
        """,
        %{table: table_name}
      )

    rows
  end

  defp projection_definitions(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name, query
        FROM system.projections
        WHERE database = currentDatabase() AND table = {table:String}
        """,
        %{table: table_name}
      )

    Enum.map_join(rows, ",\n  ", fn [name, query] -> "PROJECTION #{name} (#{query})" end)
  end

  defp index_definitions(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name, type_full, expr, granularity
        FROM system.data_skipping_indices
        WHERE database = currentDatabase() AND table = {table:String}
        """,
        %{table: table_name}
      )

    Enum.map_join(rows, ",\n  ", fn [name, type_full, expr, granularity] ->
      "INDEX #{name} (#{expr}) TYPE #{type_full} GRANULARITY #{granularity}"
    end)
  end
end
