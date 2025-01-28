defmodule Tuist.Repo.Migrations.AddXcodeProjectsTable do
  use Ecto.Migration

  def change do
    create table(:xcode_projects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false

      add :xcode_graph_id, references(:xcode_graphs, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:xcode_projects, [:xcode_graph_id, :name])
  end
end
