defmodule Tuist.IngestRepo.Migrations.RecreateActiveDailyStatsWithExactPresence do
  @moduledoc """
  Recreates `test_case_runs_active_daily_stats` as exact daily test-case
  presence rows with monthly partitions.

  The previous aggregate used `uniqExactState(test_case_id)`, which made every
  rolling active-test-case query merge exact UUID sets from the selected daily
  states. Heavy projects can accumulate enough active test cases that
  `uniqExactMerge` allocates gigabytes per query even though the table has only
  a few thousand daily aggregate rows.

  The product needs exact active test-case counts, so this migration keeps
  exactness by storing one presence row per `(project_id, date, is_ci,
  test_case_id)` instead of an exact aggregate-state blob per day. Queries can
  count exact active test cases by grouping `test_case_id` over the 14-day
  window. The table is partitioned by month so date-range scans do not sit in
  one ever-growing partition.

  The replacement table and MV are built alongside the existing objects first.
  The replacement MV captures live writes while the backfill walks source
  partitions. After the table swap, the canonical MV is recreated with the
  canonical target table and a small catch-up backfill covers the short DDL
  window. Duplicate presence rows are harmless because readers group by
  `test_case_id`.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "test_case_runs_active_daily_stats"
  @mv @table <> "_mv"
  @replacement_table @table <> "_replacement"
  @replacement_mv @mv <> "_replacement"

  def up do
    migration_started_at = DateTime.utc_now()

    replace_active_daily_stats(
      table_shape: :presence,
      migration_started_at: migration_started_at
    )
  end

  def down do
    migration_started_at = DateTime.utc_now()

    replace_active_daily_stats(
      table_shape: :exact_state,
      migration_started_at: migration_started_at
    )
  end

  defp replace_active_daily_stats(opts) do
    table_shape = Keyword.fetch!(opts, :table_shape)
    migration_started_at = Keyword.fetch!(opts, :migration_started_at)

    IngestRepo.query!("DROP VIEW IF EXISTS #{@replacement_mv}")
    IngestRepo.query!("DROP TABLE IF EXISTS #{@replacement_table}")

    create_replacement_table(table_shape)
    create_materialized_view(@replacement_mv, @replacement_table, table_shape)
    backfill_by_partition(@replacement_table, table_shape)

    IngestRepo.query!("DROP VIEW IF EXISTS #{@mv}")
    IngestRepo.query!("DROP VIEW IF EXISTS #{@replacement_mv}")
    IngestRepo.query!("EXCHANGE TABLES #{@table} AND #{@replacement_table}")
    create_materialized_view(@mv, @table, table_shape)
    backfill_since(@table, table_shape, migration_started_at)
    IngestRepo.query!("DROP TABLE IF EXISTS #{@replacement_table}")
  end

  defp create_replacement_table(:presence) do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS #{@replacement_table} (
      project_id Int64,
      date Date,
      is_ci Bool,
      test_case_id UUID
    ) ENGINE = MergeTree
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, date, is_ci, test_case_id)
    """)
  end

  defp create_replacement_table(:exact_state) do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS #{@replacement_table} (
      project_id Int64,
      date Date,
      is_ci Bool,
      test_case_ids_state AggregateFunction(uniqExact, UUID)
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, date, is_ci)
    """)
  end

  defp create_materialized_view(view_name, target_table, :presence) do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{view_name}
    TO #{target_table}
    AS SELECT
      project_id,
      date,
      is_ci,
      test_case_id
    FROM (
      SELECT
        project_id,
        toDate(ran_at) AS date,
        is_ci,
        assumeNotNull(test_case_id) AS test_case_id
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL
    )
    GROUP BY project_id, date, is_ci, test_case_id
    """)
  end

  defp create_materialized_view(view_name, target_table, :exact_state) do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{view_name}
    TO #{target_table}
    AS SELECT
      project_id,
      toDate(ran_at) AS date,
      is_ci,
      uniqExactState(assumeNotNull(test_case_id)) AS test_case_ids_state
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, toDate(ran_at), is_ci
    """)
  end

  defp backfill_by_partition(target_table, table_shape) do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: "test_case_runs"}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling partition #{partition} into #{target_table}")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          backfill_query(target_table, table_shape, """
          toYYYYMM(inserted_at) = {partition:UInt32}
          """),
          %{partition: String.to_integer(partition)},
          timeout: 1_200_000
        )
      end)
    end
  end

  defp backfill_since(target_table, table_shape, migration_started_at) do
    Logger.info("Backfilling recent rows into #{target_table}")

    retry_on_shutting_down(fn ->
      IngestRepo.query!(
        backfill_query(target_table, table_shape, """
        inserted_at >= parseDateTime64BestEffort({migration_started_at:String}, 6)
        """),
        %{migration_started_at: DateTime.to_iso8601(migration_started_at)},
        timeout: 1_200_000
      )
    end)
  end

  defp backfill_query(target_table, :presence, time_filter) do
    """
    INSERT INTO #{target_table}
    SELECT
      project_id,
      date,
      is_ci,
      test_case_id
    FROM (
      SELECT
        project_id,
        toDate(ran_at) AS date,
        is_ci,
        assumeNotNull(test_case_id) AS test_case_id
      FROM test_case_runs
      WHERE #{time_filter} AND test_case_id IS NOT NULL
    )
    GROUP BY project_id, date, is_ci, test_case_id
    """
  end

  defp backfill_query(target_table, :exact_state, time_filter) do
    """
    INSERT INTO #{target_table}
    SELECT
      project_id,
      toDate(ran_at) AS date,
      is_ci,
      uniqExactState(assumeNotNull(test_case_id)) AS test_case_ids_state
    FROM test_case_runs
    WHERE #{time_filter} AND test_case_id IS NOT NULL
    GROUP BY project_id, toDate(ran_at), is_ci
    """
  end

  defp retry_on_shutting_down(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(e.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
