defmodule Tuist.IngestRepo.Migrations.RecreateActiveDailyStatsAsReplacing do
  @moduledoc """
  Recreates `test_case_runs_active_daily_stats` as a `ReplacingMergeTree` so
  duplicate presence rows collapse on merge.

  The table stores one presence row per `(project_id, date, is_ci,
  test_case_id)`, but its `MergeTree` engine never deduplicates: the MV only
  groups within a single insert block, so every insert block that touches a
  test case on a given day writes another identical presence row. In production
  this reached a ~155x duplication factor for busy projects (project 2382: a
  14-day window held 56.8M presence rows for only 366K distinct
  `(project, date, is_ci, test_case_id)` tuples / 35.8K distinct test cases).

  `active_test_cases_count/5` (`Tuist.Tests.Analytics`) counts distinct active
  test cases over the trailing 14-day window at every chart bucket, so each call
  scanned tens of millions of duplicate rows (~1.4 GiB read) and drove the
  "Slow ClickHouse query" alert (p90 ~1.5s). The reader already `GROUP BY
  test_case_id`, so it stays correct against un-merged parts — the engine change
  only reduces how many rows it has to read.

  `ReplacingMergeTree` with `ORDER BY (project_id, date, is_ci, test_case_id)`
  (every column is a sort key) collapses exact-duplicate presence rows on merge.
  Validated locally: identical result (35,771), 57.5M -> 371K rows read, 1.39
  GiB -> 9.2 MiB, ~18x faster.

  ## Migration strategy

  Mirrors `RecreateActiveDailyStatsWithExactPresence` (replacement table + live
  capture MV + EXCHANGE swap), with two differences:

    * the replacement table is a `ReplacingMergeTree`, and
    * the historical bulk backfill reads the EXISTING presence table
      (~836M rows / 2.6 GiB, deduped per monthly partition) instead of raw
      `test_case_runs` (~5.8B rows). Reading the already-aggregated presence
      table is far lighter and keeps the deploy off the raw fact table.

  The replacement MV is created before the backfill so live writes during the
  partition loop are captured. Duplicate presence rows across the backfill, the
  replacement MV, and the post-swap catch-up are harmless — `ReplacingMergeTree`
  collapses them and the reader groups by `test_case_id` regardless.
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
    swap_engine("ReplacingMergeTree", DateTime.utc_now())
  end

  def down do
    swap_engine("MergeTree", DateTime.utc_now())
  end

  defp swap_engine(engine, migration_started_at) do
    IngestRepo.query!("DROP VIEW IF EXISTS #{@replacement_mv}")
    IngestRepo.query!("DROP TABLE IF EXISTS #{@replacement_table}")

    create_presence_table(@replacement_table, engine)
    create_presence_mv(@replacement_mv, @replacement_table)
    backfill_history(@replacement_table)

    IngestRepo.query!("DROP VIEW IF EXISTS #{@mv}")
    IngestRepo.query!("DROP VIEW IF EXISTS #{@replacement_mv}")
    IngestRepo.query!("EXCHANGE TABLES #{@table} AND #{@replacement_table}")
    create_presence_mv(@mv, @table)
    catch_up(@table, migration_started_at)
    IngestRepo.query!("DROP TABLE IF EXISTS #{@replacement_table}")
  end

  defp create_presence_table(table, engine) do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS #{table} (
      project_id Int64,
      date Date,
      is_ci Bool,
      test_case_id UUID
    ) ENGINE = #{engine}
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, date, is_ci, test_case_id)
    """)
  end

  defp create_presence_mv(view_name, target_table) do
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

  # Bulk history from the existing presence table, one monthly partition at a
  # time. The source is sorted by exactly the GROUP BY keys, so the dedup is a
  # streaming aggregation with bounded memory.
  defp backfill_history(target_table) do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: @table}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling partition #{partition} into #{target_table}")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO #{target_table}
          SELECT project_id, date, is_ci, test_case_id
          FROM #{@table}
          WHERE toYYYYMM(date) = {partition:UInt32}
          GROUP BY project_id, date, is_ci, test_case_id
          """,
          %{partition: String.to_integer(partition)},
          timeout: 1_200_000
        )
      end)
    end
  end

  # Covers writes during the DDL/backfill window from the source of truth.
  # Recent-only (`inserted_at >= migration_started_at`), so it is bounded and
  # does not scan the raw fact table's history.
  defp catch_up(target_table, migration_started_at) do
    Logger.info("Catch-up backfill into #{target_table}")

    retry_on_shutting_down(fn ->
      IngestRepo.query!(
        """
        INSERT INTO #{target_table}
        SELECT project_id, date, is_ci, test_case_id
        FROM (
          SELECT
            project_id,
            toDate(ran_at) AS date,
            is_ci,
            assumeNotNull(test_case_id) AS test_case_id
          FROM test_case_runs
          WHERE inserted_at >= parseDateTime64BestEffort({migration_started_at:String}, 6)
            AND test_case_id IS NOT NULL
        )
        GROUP BY project_id, date, is_ci, test_case_id
        """,
        %{migration_started_at: DateTime.to_iso8601(migration_started_at)},
        timeout: 1_200_000
      )
    end)
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
