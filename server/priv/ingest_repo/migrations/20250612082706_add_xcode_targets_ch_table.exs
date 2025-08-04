defmodule Tuist.ClickHouseRepo.Migrations.AddXcodeTargetsChTable do
  use Ecto.Migration

  def change do
    create table(:xcode_targets,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (xcode_project_id, inserted_at)"
           ) do
      add :id, :string, null: false
      add :name, :string, null: false
      add :binary_cache_hash, :"Nullable(String)"
      add :binary_cache_hit, :"Enum8('miss' = 0, 'local' = 1, 'remote' = 2)", null: false
      add :selective_testing_hash, :"Nullable(String)"
      add :selective_testing_hit, :"Enum8('miss' = 0, 'local' = 1, 'remote' = 2)", null: false
      add :xcode_project_id, :string, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
