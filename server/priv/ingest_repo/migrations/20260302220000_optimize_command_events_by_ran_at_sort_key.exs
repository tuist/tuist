defmodule Tuist.IngestRepo.Migrations.OptimizeCommandEventsByRanAtSortKey do
  @moduledoc """
  Recreates the `command_events_by_ran_at` materialized view with an optimized
  sort key: ORDER BY (project_id, ran_at) instead of (project_id, name, ran_at).

  With `name` between `project_id` and `ran_at` in the sort key, queries that
  filter with `name IN (...)` and sort by `ran_at DESC LIMIT N` cannot use
  ClickHouse's read-in-order optimization. ClickHouse must read ALL matching
  rows for each (project_id, name) group and then merge-sort them — resulting
  in ~432K rows read for just 20 result rows.

  By removing `name` from the sort key, data for each project_id is sorted
  contiguously by ran_at. ClickHouse can read backwards from the latest ran_at
  and apply the `name` filter as a lightweight predicate, stopping as soon as
  LIMIT is satisfied. This reduces reads from ~432K rows to ~8K (one granule).
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
    POPULATE
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
