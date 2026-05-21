defmodule Tuist.IngestRepo.Migrations.AddDurationToCasEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE cas_events ADD COLUMN IF NOT EXISTS duration_ms Int64 DEFAULT 0"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS cas_events_daily_stats_mv"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE cas_events_daily_stats
      ADD COLUMN IF NOT EXISTS total_duration_ms SimpleAggregateFunction(sum, Int64)
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
      count() AS event_count,
      sum(duration_ms) AS total_duration_ms
    FROM cas_events
    GROUP BY project_id, action, date
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS cas_events_daily_stats_mv"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE cas_events_daily_stats DROP COLUMN IF EXISTS total_duration_ms"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE cas_events DROP COLUMN IF EXISTS duration_ms"

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
  end
end
