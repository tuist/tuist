defmodule Tuist.IngestRepo.Migrations.AddCustomTagsToBundles do
  use Ecto.Migration

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:bundles) do
      add :custom_tags, :"Array(String)"
    end

    # ClickHouse ADD INDEX is metadata-only; PostgreSQL concurrent-index rules do not apply.
    # excellent_migrations:safety-assured-for-next-line index-not-concurrently
    create index(:bundles, [:custom_tags],
             name: :idx_bundle_custom_tags,
             options: "TYPE bloom_filter(0.01) GRANULARITY 1"
           )

    flush()

    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    # Bound each asynchronous index mutation to one existing partition.
    IngestRepo
    |> IndexMaterialization.partition_ids(database, "bundles")
    |> then(
      &IndexMaterialization.materialize_index_statements(
        database,
        "bundles",
        "idx_bundle_custom_tags",
        &1
      )
    )
    # excellent_migrations:safety-assured-for-next-line raw-sql-executed
    |> Enum.each(&execute/1)
  end

  def down do
    # ClickHouse DROP INDEX is metadata-only, like ADD INDEX above.
    # excellent_migrations:safety-assured-for-next-line index-not-concurrently
    drop index(:bundles, [:custom_tags], name: :idx_bundle_custom_tags)

    alter table(:bundles) do
      # An explicit rollback discards the labels introduced by this migration.
      # excellent_migrations:safety-assured-for-next-line column-removed
      remove :custom_tags
    end
  end
end
