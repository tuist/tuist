defmodule Tuist.ClickHouseRepo.Migrations.AddBuildTargetsTable do
  use Ecto.Migration

  def change do
    create table(:build_targets,
             primary_key: false,
             engine: "MergeTree",
             options:
               "ORDER BY (build_run_id, compilation_duration, build_duration, name, project, status, inserted_at)"
           ) do
      add :name, :string, null: false
      add :project, :string, null: false
      add :compilation_duration, :UInt64, null: false
      add :build_duration, :UInt64, null: false
      add :build_run_id, :uuid, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
