defmodule Tuist.ClickHouseRepo.Migrations.AddBuildFilesTable do
  use Ecto.Migration

  def change do
    create table(:build_files,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (build_run_id, compilation_duration, path, inserted_at)"
           ) do
      add :type, :"Enum8('swift' = 0, 'c' = 1)", null: false
      add :target, :string, null: false
      add :project, :string, null: false
      add :path, :string, null: false
      add :compilation_duration, :UInt64, null: false
      add :build_run_id, :uuid, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
