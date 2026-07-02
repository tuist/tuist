defmodule Tuist.IngestRepo.Migrations.CreateModuleCacheOutputs do
  use Ecto.Migration

  def change do
    create table(:module_cache_outputs,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, command_event_id, operation, inserted_at)"
           ) do
      add :command_event_id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :operation, :"Enum8('download' = 0, 'upload' = 1)", null: false
      add :name, :string, null: false
      add :hash, :string, null: false
      add :size, :UInt64, null: false
      add :compressed_size, :UInt64, null: false
      add :duration, :UInt64, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
