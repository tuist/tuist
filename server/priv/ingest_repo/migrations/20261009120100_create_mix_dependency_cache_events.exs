defmodule Tuist.IngestRepo.Migrations.CreateMixDependencyCacheEvents do
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  def change do
    create table(:mix_dependency_cache_events,
             primary_key: false,
             engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, build_id, dependency) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :project_id, :Int64, null: false
      add :build_id, :uuid, null: false
      add :dependency, :string, null: false
      add :outcome, :"LowCardinality(String)", null: false
      add :reason, :"LowCardinality(String)", null: false, default: ""
      add :key, :string, null: false, default: ""
      add :duration_ms, :UInt32, null: false, default: 0
      add :saved_duration_ms, :"Nullable(UInt32)"
      add :is_ci, :Bool, null: false, default: false
      add :mix_env, :"LowCardinality(String)", null: false, default: ""
      add :git_branch, :string, null: false, default: ""
      add :inserted_at, :"DateTime('UTC')", null: false, default: fragment("now('UTC')")
    end
  end
end
