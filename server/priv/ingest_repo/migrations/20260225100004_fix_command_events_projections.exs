defmodule Tuist.IngestRepo.Migrations.FixCommandEventsProjections do
  @moduledoc """
  Fixes the broken projection and creates a materialized view sorted by duration.

  The existing projection `projection_by_project_name_hit_rate` was created before
  the `test_run_id` and `cache_endpoint` columns were added. ClickHouse cannot use
  a projection that is missing columns referenced by the query, so it has been
  silently unused. We drop it here.

  Normal (non-aggregate) projections in ClickHouse only help with data filtering
  (granule pruning), NOT with ORDER BY optimization. Since the main table's primary
  key (project_id, name, ran_at) already efficiently filters on project_id and name,
  adding normal projections with different sort orders provides no benefit.

  Instead, we create a materialized view `command_events_by_duration` with
  ORDER BY (project_id, name, duration). This allows ClickHouse to use
  `optimize_read_in_order` for ORDER BY duration DESC queries, reading only
  a few granules instead of scanning all matching rows.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Drop the broken projection (missing test_run_id and cache_endpoint columns).
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP PROJECTION IF EXISTS projection_by_project_name_hit_rate SETTINGS mutations_sync = 1"

    # Materialized view with its own implicit storage sorted by duration.
    # Automatically inserts into its storage on every write to command_events.
    # POPULATE backfills existing data at creation time.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_duration
    ENGINE = MergeTree
    ORDER BY (project_id, name, duration)
    SETTINGS index_granularity = 8192
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_duration"
  end
end
