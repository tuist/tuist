defmodule Tuist.IngestRepo.Migrations.CreateGradleCacheEventsTable do
  use Ecto.Migration

  def change do
    create table(:gradle_cache_events,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, action, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :action, :"Enum8('upload' = 0, 'download' = 1)", null: false
      add :cache_key, :string, null: false
      add :size, :Int64, null: false
      add :duration_ms, :UInt64, null: false, default: 0
      add :is_hit, :Bool, null: false, default: true
      add :project_id, :Int64, null: false
      add :account_handle, :string, null: false
      add :project_handle, :string, null: false
      add :is_ci, :Bool, default: false
      add :gradle_build_id, :"Nullable(UUID)"
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
