defmodule Tuist.IngestRepo.Migrations.AddInsertedAtIndexToXcodeGraphs do
  @moduledoc """
  Adds a `minmax` skip index on `xcode_graphs.inserted_at`.

  `xcode_graphs` is `ORDER BY (id, inserted_at)`. `id` is a UUIDv7 (time-ordered),
  so the table is physically clustered by insertion time, but `inserted_at` is a
  non-leading sort key with no skip index. `build_time_analytics/1`
  (`SELECT sum(duration), sum(binary_build_duration) FROM xcode_graphs JOIN
  command_events ... WHERE inserted_at BETWEEN ? AND ? AND project_id = ?`) filters
  only on `inserted_at`, which the primary key cannot prune ("generic exclusion
  search"), so every dashboard load full-scans the whole table. The cost grows
  unboundedly with total table size and drove the "Slow ClickHouse query" alert
  (p90 ~1.8s).

  A `minmax` index on `inserted_at` lets ClickHouse skip granules outside the
  requested window. Because the data is time-clustered the min/max ranges are
  tight, so a 30-day window reads ~1/6 of the granules instead of all of them
  (validated locally: 1302/1302 -> 222/1302 granules, 11.0M -> 2.1M read rows).

  `ADD INDEX` is metadata-only. `MATERIALIZE INDEX` builds the index for existing
  parts as a background mutation and returns immediately (async), so it does not
  block the deploy.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_graphs
    ADD INDEX IF NOT EXISTS idx_inserted_at inserted_at TYPE minmax GRANULARITY 4
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_graphs MATERIALIZE INDEX idx_inserted_at"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_graphs DROP INDEX IF EXISTS idx_inserted_at"
  end
end
