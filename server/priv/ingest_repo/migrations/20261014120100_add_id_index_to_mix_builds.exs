defmodule Tuist.IngestRepo.Migrations.AddIdIndexToMixBuilds do
  @moduledoc """
  Adds a bloom filter skip index on `mix_builds.id`.

  `mix_builds` is `ORDER BY (project_id, inserted_at, id)`, so a lookup of
  specific builds (`project_id = ? AND id IN (...)`) can only prune to the
  project: `id` follows `inserted_at` in the key and does not narrow the
  search on its own. Build entity history resolves up to 100 parent builds
  per page that way, and `Mix.get_build/2` looks a build up by ID too. Build
  IDs are random client UUIDs, but a page's builds were inserted close
  together and so sit in few granules, which is what lets the bloom filter
  skip the rest.

  A skip index rather than an ID-ordered projection: the table is append-only
  `MergeTree` read by a handful of IDs at a time, an index costs a few bytes
  per row instead of a second copy of every row, and it changes neither
  results nor the latest-version (`argMax` tuple) semantics of the readers.

  `ADD INDEX` is metadata-only and covers new parts. Existing parts are
  indexed by one asynchronous `MATERIALIZE INDEX` mutation per partition
  (`SchemaClone.materialize_index_statements/4`), so each unit of work is one
  partition, reads only the `id` column, and the deploy does not wait for
  any of it. Parts not yet materialized are still read correctly, only
  without skipping. The in-cluster ClickHouse gets the same index and the
  same bounded materialization from `SchemaClone.reconcile/1`, which runs
  after migrations on every deploy.
  """
  use Ecto.Migration

  alias Tuist.ClickHouse.SchemaClone
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE mix_builds
    ADD INDEX IF NOT EXISTS idx_id id
    TYPE bloom_filter GRANULARITY 1
    """

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    IngestRepo
    |> SchemaClone.partition_ids(database, "mix_builds")
    |> then(&SchemaClone.materialize_index_statements(database, "mix_builds", "idx_id", &1))
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    |> Enum.each(&execute/1)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE mix_builds DROP INDEX IF EXISTS idx_id"
  end
end
