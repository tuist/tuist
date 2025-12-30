defmodule Tuist.ClickHouseRepo.Migrations.AddXcodeProjectsChTable do
  use Ecto.Migration

  def change do
    create table(:xcode_projects,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (xcode_graph_id, name, inserted_at)"
           ) do
      add :id, :string, null: false
      add :name, :string, null: false
      add :path, :string, null: false
      add :xcode_graph_id, :string, null: false
      add :inserted_at, :timestamp, default: fragment("now()")
    end
  end
end
