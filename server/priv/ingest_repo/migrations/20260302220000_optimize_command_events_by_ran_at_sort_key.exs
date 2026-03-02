defmodule Tuist.IngestRepo.Migrations.OptimizeCommandEventsByRanAtSortKey do
  @moduledoc """
  Recreates `command_events_by_ran_at` with ORDER BY (project_id, ran_at)
  instead of (project_id, name, ran_at).

  With `name` between `project_id` and `ran_at` in the sort key, queries that
  filter with `name IN (...)` and sort by `ran_at DESC LIMIT N` cannot use
  ClickHouse's read-in-order optimization. ClickHouse reads ALL matching rows
  (~432K avg in production) then merge-sorts them for just ~20 result rows.

  Removing `name` from the sort key lets ClickHouse read backwards from the
  latest ran_at and apply the name filter as a lightweight predicate, stopping
  at LIMIT. This reduces reads from ~432K to ~8K rows (one granule).

  The view is created WITHOUT POPULATE so the DDL is instant and new writes
  flow immediately. Historical data is backfilled in a separate migration to
  follow the same split pattern used for projections on ClickHouse Cloud.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, ran_at)
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """
  end
end
