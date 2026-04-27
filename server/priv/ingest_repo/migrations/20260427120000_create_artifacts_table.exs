defmodule Tuist.IngestRepo.Migrations.CreateArtifactsTable do
  use Ecto.Migration

  def up do
    create table(:artifacts,
             primary_key: false,
             engine: "ReplacingMergeTree(updated_at)",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (bundle_id, id) SETTINGS index_granularity = 8192"
           ) do
      add :id, :uuid, null: false
      add :bundle_id, :uuid, null: false

      add :artifact_type,
          :"Enum8('directory' = 0, 'file' = 1, 'font' = 2, 'binary' = 3, 'localization' = 4, 'asset' = 5, 'unknown' = 6)",
          null: false

      add :path, :string, null: false
      add :size, :Int64, null: false
      add :shasum, :string, null: false
      add :artifact_id, :"Nullable(UUID)"

      add :inserted_at, :"DateTime64(6)", default: fragment("now64(6)"), null: false
      add :updated_at, :"DateTime64(6)", default: fragment("now64(6)"), null: false
    end

    # Bloom filter on artifact_id supports server-side parent filtering when the
    # in-memory tree builder is replaced with a paginated CH-side query.
    execute(
      "ALTER TABLE artifacts ADD INDEX idx_artifact_id (artifact_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:artifacts)
  end
end
