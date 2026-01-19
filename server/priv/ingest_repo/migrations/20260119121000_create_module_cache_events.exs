defmodule Tuist.IngestRepo.Migrations.CreateModuleCacheEvents do
  use Ecto.Migration

  def change do
    create table(:module_cache_events,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, run_id, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :run_id, :string, null: false
      add :source, :"Enum8('disk' = 0, 's3' = 1)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
