defmodule Tuist.Repo.Migrations.DropXcodeTables do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:xcode_targets)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:xcode_projects)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:xcode_graphs)
  end

  def down do
    # Recreate tables in reverse order to satisfy foreign key constraints
    create table(:xcode_graphs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :command_event_id, :id, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:xcode_graphs, [:command_event_id])

    create table(:xcode_projects, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false

      add :xcode_graph_id, references(:xcode_graphs, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:xcode_projects, [:xcode_graph_id, :name])

    create table(:xcode_targets, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :binary_cache_hash, :string
      add :binary_cache_hit, :integer
      add :selective_testing_hash, :string
      add :selective_testing_hit, :integer

      add :xcode_project_id,
          references(:xcode_projects, type: :uuid, on_delete: :delete_all),
          null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:xcode_targets, [:xcode_project_id, :name])
  end
end
