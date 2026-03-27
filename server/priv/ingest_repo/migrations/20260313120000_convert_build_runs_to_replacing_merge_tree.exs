defmodule Tuist.IngestRepo.Migrations.ConvertBuildRunsToReplacingMergeTree do
  @moduledoc """
  Converts the build_runs table from MergeTree to ReplacingMergeTree(inserted_at)
  to support deduplication when builds transition from "processing" to their final status.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        "SELECT engine FROM system.tables WHERE database = currentDatabase() AND name = {table:String}",
        %{table: "build_runs"}
      )

    case rows do
      [["ReplacingMergeTree"]] ->
        Logger.info("build_runs is already ReplacingMergeTree, skipping conversion")

      _ ->
        IngestRepo.query!("DROP TABLE IF EXISTS build_runs_new")

        columns = get_column_definitions("build_runs")
        indexes = get_index_definitions("build_runs")

        IngestRepo.query!("""
        CREATE TABLE build_runs_new (
          #{columns}#{if indexes != "", do: ",\n  #{indexes}", else: ""}
        ) ENGINE = ReplacingMergeTree(inserted_at)
        PARTITION BY toYYYYMM(inserted_at)
        ORDER BY (project_id, inserted_at, id)
        """)

        IngestRepo.query!(
          "INSERT INTO build_runs_new SELECT * FROM build_runs",
          [],
          timeout: 1_200_000
        )

        IngestRepo.query!("RENAME TABLE build_runs TO build_runs_old")
        IngestRepo.query!("RENAME TABLE build_runs_new TO build_runs")

        Logger.info("Completed converting build_runs to ReplacingMergeTree")
    end
  end

  def down do
    :ok
  end

  defp get_column_definitions(table_name) do
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
    |> Enum.map(fn [name, type, default_kind, default_expression] ->
      default_clause =
        case default_kind do
          "DEFAULT" -> " DEFAULT #{default_expression}"
          _ -> ""
        end

      "#{name} #{type}#{default_clause}"
    end)
    |> Enum.join(",\n  ")
  end

  defp get_index_definitions(table_name) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT name, type_full, expr, granularity
        FROM system.data_skipping_indices
        WHERE database = currentDatabase() AND table = {table:String}
        """,
        %{table: table_name}
      )

    rows
    |> Enum.map(fn [name, type_full, expr, granularity] ->
      "INDEX #{name} (#{expr}) TYPE #{type_full} GRANULARITY #{granularity}"
    end)
    |> Enum.join(",\n  ")
  end
end
