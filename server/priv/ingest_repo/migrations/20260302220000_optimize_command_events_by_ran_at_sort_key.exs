defmodule Tuist.IngestRepo.Migrations.OptimizeCommandEventsMvSortKeys do
  @moduledoc """
  Recreates `command_events_by_ran_at` and `command_events_by_duration` with
  `name` removed from the sort key.

  The views previously used ORDER BY (project_id, name, <sort_column>). With
  `name` between `project_id` and the sort column, queries that filter with
  `name IN (...)` and sort by the target column cannot use ClickHouse's
  read-in-order optimization — ClickHouse reads ALL matching rows and then
  merge-sorts them.

  Removing `name` from the sort key lets ClickHouse read directly in sort
  order within each project, applying the name filter as a lightweight
  predicate. This reduces reads from ~180K to ~8K rows (one granule).

  Note: `command_events_by_hit_rate` is NOT changed because `hit_rate` is
  Float32 and ClickHouse does not use the read-in-order optimization for
  float sort keys (EXPLAIN PLAN shows ReadType: Default instead of
  InReverseOrder). Keeping `name` in its sort key is better since it at
  least narrows the scan range.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_duration SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_duration
    ENGINE = MergeTree
    ORDER BY (project_id, duration)
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_duration SYNC"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_duration
    ENGINE = MergeTree
    ORDER BY (project_id, name, duration)
    POPULATE
    AS SELECT * FROM command_events
    """
  end
end
