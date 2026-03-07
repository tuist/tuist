defmodule Tuist.IngestRepo.Migrations.CreateCasEventsDailyStatsMv do
  @moduledoc """
  Creates a materialized view that pre-aggregates CAS events into daily stats.

  The `cas_events` table stores individual upload/download events and is queried
  with `SUM(size)` grouped by date intervals. With ~12M rows read on average,
  the p90 latency reaches ~1.9s and p99 ~4.4s.

  This materialized view pre-computes daily `SUM(size)` and `count()` per
  (project_id, action, date), reducing row reads from millions to at most
  hundreds (one row per day per action). The analytics queries can then
  re-aggregate these daily totals into coarser intervals (week, month) cheaply.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TABLE IF NOT EXISTS cas_events_daily_stats (
      project_id Int64,
      action Enum8('upload' = 0, 'download' = 1),
      date Date,
      total_size SimpleAggregateFunction(sum, Int64),
      event_count SimpleAggregateFunction(sum, UInt64)
    )
    ENGINE = AggregatingMergeTree
    ORDER BY (project_id, action, date)
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS cas_events_daily_stats_mv
    TO cas_events_daily_stats
    AS SELECT
      project_id,
      action,
      toDate(inserted_at) AS date,
      sum(size) AS total_size,
      count() AS event_count
    FROM cas_events
    GROUP BY project_id, action, date
    """

    # Backfill from existing data
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO cas_events_daily_stats
    SELECT
      project_id,
      action,
      toDate(inserted_at) AS date,
      sum(size) AS total_size,
      count() AS event_count
    FROM cas_events
    GROUP BY project_id, action, date
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS cas_events_daily_stats_mv"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP TABLE IF EXISTS cas_events_daily_stats"
  end
end
