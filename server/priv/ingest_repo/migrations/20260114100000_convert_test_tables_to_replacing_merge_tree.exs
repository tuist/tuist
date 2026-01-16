defmodule Tuist.IngestRepo.Migrations.ConvertTestTablesToReplacingMergeTree do
  @moduledoc """
  Converts test_runs, test_module_runs, test_suite_runs, and test_case_runs tables
  from MergeTree to ReplacingMergeTree(inserted_at) to support updates.

  This enables updating the is_flaky flag on historical runs when cross-run
  flaky tests are detected (e.g., same test on same commit passes in one CI run
  but fails in another).

  Uses batch migration to handle large tables safely.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 100_000
  @throttle_ms 1000

  @table_order_by %{
    "test_runs" => "ORDER BY (project_id, id)",
    "test_module_runs" => "ORDER BY (test_run_id, id)",
    "test_suite_runs" => "ORDER BY (test_run_id, test_module_run_id, id)",
    "test_case_runs" => "ORDER BY (test_run_id, test_module_run_id, id)"
  }

  @table_original_order_by %{
    "test_runs" => "ORDER BY (project_id, ran_at, id)",
    "test_module_runs" => "ORDER BY (test_run_id, inserted_at, id)",
    "test_suite_runs" => "ORDER BY (test_run_id, test_module_run_id, inserted_at, id)",
    "test_case_runs" => "ORDER BY (test_run_id, test_module_run_id, inserted_at, id)"
  }

  def up do
    convert_table("test_runs")
    convert_table("test_module_runs")
    convert_table("test_suite_runs")
    convert_table("test_case_runs")
  end

  def down do
    revert_table("test_case_runs")
    revert_table("test_suite_runs")
    revert_table("test_module_runs")
    revert_table("test_runs")
  end

  defp convert_table(table_name) do
    Logger.info("Converting #{table_name} to ReplacingMergeTree...")

    # Check if table is already ReplacingMergeTree
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        "SELECT engine FROM system.tables WHERE database = currentDatabase() AND name = {table:String}",
        %{table: table_name}
      )

    case rows do
      [["ReplacingMergeTree"]] ->
        Logger.info("#{table_name} is already ReplacingMergeTree, skipping conversion")

      _ ->
        new_table = "#{table_name}_new"
        old_table = "#{table_name}_old"
        order_by = Map.fetch!(@table_order_by, table_name)

        # Clean up any leftover temporary tables from previous failed runs
        # Use SYNC to ensure operations complete across all replicas in ClickHouse Cloud
        IngestRepo.query!("DROP TABLE IF EXISTS #{new_table} SYNC")
        IngestRepo.query!("DROP TABLE IF EXISTS #{old_table} SYNC")

        # Get column definitions from existing table
        columns = get_column_definitions(table_name)
        indexes = get_index_definitions(table_name)

        # Create new table with ReplacingMergeTree using the same schema
        IngestRepo.query!("""
        CREATE TABLE #{new_table} (
          #{columns}#{if indexes != "", do: ",\n  #{indexes}", else: ""}
        ) ENGINE = ReplacingMergeTree(inserted_at)
        PARTITION BY toYYYYMM(inserted_at)
        #{order_by}
        """)

        # Copy data in batches using cursor-based pagination on inserted_at
        copy_data_in_batches(table_name, new_table)

        # Swap tables (separate queries for ClickHouse Shared database compatibility)
        # Use SYNC to ensure operations complete across all replicas in ClickHouse Cloud
        IngestRepo.query!("RENAME TABLE #{table_name} TO #{old_table} SYNC")
        IngestRepo.query!("RENAME TABLE #{new_table} TO #{table_name} SYNC")

        # Keep old table for safety - will be dropped in a follow-up migration

        Logger.info("Completed converting #{table_name}")
    end
  end

  defp revert_table(table_name) do
    Logger.info("Reverting #{table_name} to MergeTree...")

    new_table = "#{table_name}_new"
    old_table = "#{table_name}_old"
    order_by = Map.fetch!(@table_original_order_by, table_name)

    # Clean up any leftover temporary tables from previous failed runs
    # Use SYNC to ensure operations complete across all replicas in ClickHouse Cloud
    IngestRepo.query!("DROP TABLE IF EXISTS #{new_table} SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS #{old_table} SYNC")

    # Get column definitions from existing table
    columns = get_column_definitions(table_name)
    indexes = get_index_definitions(table_name)

    # Create new table with MergeTree
    IngestRepo.query!("""
    CREATE TABLE #{new_table} (
      #{columns}#{if indexes != "", do: ",\n  #{indexes}", else: ""}
    ) ENGINE = MergeTree
    PARTITION BY toYYYYMM(inserted_at)
    #{order_by}
    """)

    # Copy data using FINAL to get deduplicated rows
    copy_data_in_batches(table_name, new_table, use_final: true)

    # Swap tables (separate queries for ClickHouse Shared database compatibility)
    # Use SYNC to ensure operations complete across all replicas in ClickHouse Cloud
    IngestRepo.query!("RENAME TABLE #{table_name} TO #{old_table} SYNC")
    IngestRepo.query!("RENAME TABLE #{new_table} TO #{table_name} SYNC")

    # Keep old table for safety - will be dropped in a follow-up migration

    Logger.info("Completed reverting #{table_name}")
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

  defp copy_data_in_batches(source_table, target_table, opts \\ []) do
    use_final = Keyword.get(opts, :use_final, false)
    final_clause = if use_final, do: "FINAL", else: ""

    do_copy_batch(source_table, target_table, final_clause, ~N[1970-01-01 00:00:00.000000], 0)
  end

  defp do_copy_batch(source_table, target_table, final_clause, last_inserted_at, total_copied) do
    # Get count of remaining rows
    {:ok, %{rows: [[count]]}} =
      IngestRepo.query(
        "SELECT count(*) FROM #{source_table} #{final_clause} WHERE inserted_at > {last_inserted_at:DateTime64(6)}",
        %{last_inserted_at: last_inserted_at}
      )

    if count == 0 do
      Logger.info("Finished copying #{source_table}: #{total_copied} total rows")
      :ok
    else
      Logger.info(
        "Copying batch from #{source_table} (#{count} remaining, #{total_copied} copied so far)..."
      )

      # Copy batch ordered by inserted_at
      {:ok, %{num_rows: rows_copied}} =
        IngestRepo.query(
          """
          INSERT INTO #{target_table}
          SELECT * FROM #{source_table} #{final_clause}
          WHERE inserted_at > {last_inserted_at:DateTime64(6)}
          ORDER BY inserted_at
          LIMIT #{@batch_size}
          """,
          %{last_inserted_at: last_inserted_at},
          timeout: :infinity
        )

      # Get the max inserted_at from the batch we just copied
      {:ok, %{rows: [[new_last_inserted_at]]}} =
        IngestRepo.query(
          """
          SELECT max(inserted_at) FROM #{target_table}
          WHERE inserted_at > {last_inserted_at:DateTime64(6)}
          """,
          %{last_inserted_at: last_inserted_at}
        )

      Process.sleep(@throttle_ms)

      do_copy_batch(
        source_table,
        target_table,
        final_clause,
        new_last_inserted_at,
        total_copied + rows_copied
      )
    end
  end
end
