defmodule Tuist.IngestRepo.Migrations.CreateGradleTasksTable do
  use Ecto.Migration

  def change do
    create table(:gradle_tasks,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (gradle_build_id, task_path, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :gradle_build_id, :uuid, null: false
      add :task_path, :string, null: false
      add :task_type, :string, null: false, default: ""

      add :outcome, :"LowCardinality(String)", null: false

      add :cacheable, :Bool, null: false, default: false
      add :duration_ms, :UInt64, null: false, default: 0
      add :cache_key, :string, null: false, default: ""
      add :cache_artifact_size, :"Nullable(Int64)"
      add :started_at, :"Nullable(DateTime64(6))"
      add :project_id, :Int64, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
