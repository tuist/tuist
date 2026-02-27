defmodule Tuist.IngestRepo.Migrations.CreateCommandEventsByRanAtMv do
  @moduledoc """
  Creates a materialized view for efficient ORDER BY ran_at DESC queries.

  The main `command_events` table is PARTITION BY toYYYYMM(ran_at) with
  ORDER BY (project_id, name, ran_at). Without a date range filter in the
  query, ClickHouse must read from every monthly partition and merge-sort
  across them to satisfy ORDER BY ran_at DESC LIMIT N — even though ran_at
  is already the third column of the sorting key.

  This materialized view stores the same data WITHOUT partitioning, so all
  rows for a given (project_id, name) are physically contiguous and sorted
  by ran_at. ClickHouse can then use optimize_read_in_order to read only
  the last N granules for the specific (project_id, name), instead of
  scanning each partition independently and merging.

  The Elixir query layer routes ORDER BY ran_at queries to this view via
  sort_optimized_table/1, matching the same pattern used for
  command_events_by_duration and command_events_by_hit_rate.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS command_events_by_ran_at
    ENGINE = MergeTree
    ORDER BY (project_id, name, ran_at)
    POPULATE
    AS SELECT * FROM command_events
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS command_events_by_ran_at"
  end
end
