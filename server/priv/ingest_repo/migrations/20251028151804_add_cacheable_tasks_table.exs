defmodule Tuist.ClickHouseRepo.Migrations.AddCacheableTasksTable do
  use Ecto.Migration

  def change do
    create table(:cacheable_tasks,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (build_run_id, key, status, inserted_at)"
           ) do
      add :type, :"Enum8('clang' = 0, 'swift' = 1)", null: false
      add :status, :"Enum8('hit_local' = 0, 'hit_remote' = 1, 'miss' = 2)", null: false
      add :key, :string, null: false
      add :build_run_id, :uuid, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
