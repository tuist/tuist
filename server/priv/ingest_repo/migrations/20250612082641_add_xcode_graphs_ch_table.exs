defmodule Tuist.ClickHouseRepo.Migrations.AddXcodeGraphsChTable do
  use Ecto.Migration

  def change do
    create table(:xcode_graphs,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (command_event_id, inserted_at)"
           ) do
      add :id, :string, null: false
      add :name, :string, null: false
      add :command_event_id, :UInt64, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
