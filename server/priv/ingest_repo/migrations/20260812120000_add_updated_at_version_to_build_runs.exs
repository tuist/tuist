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

  The old table is left behind as `build_runs_new` so the swap can be undone;
  a follow-up migration drops it once the new table has been verified, the
  same sequence used by the previous `build_runs` swap.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Rows written to the old table between the copy's snapshot and the exchange
  # would otherwise be lost. The tail copy replays a window wide enough to
  # cover that gap plus ingestion buffers that flush on a delay; re-inserting
  # rows already copied is harmless because the engine dedups them.
  @tail_copy_window_minutes 10

  def up do
    IngestRepo.query!("DROP TABLE IF EXISTS build_runs_new")

    started_at = DateTime.utc_now()
    columns = column_names("build_runs")
    column_definitions = column_definitions("build_runs")
    indexes = index_definitions("build_runs")

    IngestRepo.query!("""
    CREATE TABLE build_runs_new (
      #{column_definitions},
      updated_at DateTime64(6) DEFAULT inserted_at#{if indexes != "", do: ",\n  #{indexes}", else: ""},
      PROJECTION proj_by_id (
        SELECT *
        ORDER BY id
      )
    ) ENGINE = ReplacingMergeTree(updated_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, id)
    SETTINGS deduplicate_merge_projection_mode = 'rebuild'
    """)

    IngestRepo.query!(
      """
      INSERT INTO build_runs_new (#{columns}, updated_at)
      SELECT #{columns}, #{version_expression()}
      FROM build_runs
      """,
      [],
      timeout: 1_200_000
    )

    IngestRepo.query!("EXCHANGE TABLES build_runs AND build_runs_new")

    tail_copy_floor = DateTime.add(started_at, -@tail_copy_window_minutes, :minute)

    IngestRepo.query!(
      """
      INSERT INTO build_runs (#{columns}, updated_at)
      SELECT #{columns}, #{version_expression()}
      FROM build_runs_new
      WHERE inserted_at >= {floor:DateTime64(6)}
      """,
      %{floor: tail_copy_floor},
      timeout: 1_200_000
    )

    Logger.info("build_runs now dedups on updated_at; previous table kept as build_runs_new")
  end

  def down do
    :ok
  end

  defp version_expression do
    "if(status = 'processing', inserted_at, addSeconds(inserted_at, 1))"
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
