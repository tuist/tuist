defmodule Tuist.IngestRepo.Migrations.CreateRegistryDownloadEventsTable do
  use Ecto.Migration

  def change do
    create table(:registry_download_events,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (scope, name, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :scope, :string, null: false
      add :name, :string, null: false
      add :version, :string, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end

    execute(
      "ALTER TABLE registry_download_events ADD INDEX registry_download_events_scope_name_index (scope, name) TYPE bloom_filter(0.01) GRANULARITY 4",
      "ALTER TABLE registry_download_events DROP INDEX IF EXISTS registry_download_events_scope_name_index"
    )

    execute(
      "ALTER TABLE registry_download_events ADD INDEX registry_download_events_inserted_at_index (inserted_at) TYPE minmax GRANULARITY 4",
      "ALTER TABLE registry_download_events DROP INDEX IF EXISTS registry_download_events_inserted_at_index"
    )
  end
end
