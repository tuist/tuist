defmodule Tuist.ClickHouseRepo.Migrations.AddCasOutputsTable do
  use Ecto.Migration

  def change do
    create table(:cas_outputs,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (build_run_id, node_id, operation, inserted_at)"
           ) do
      add :node_id, :string, null: false
      add :checksum, :string, null: false
      add :size, :UInt64, null: false
      add :duration, :UInt64, null: false
      add :compressed_size, :UInt64, null: false
      add :operation, :"Enum8('download' = 0, 'upload' = 1)", null: false
      add :build_run_id, :uuid, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
