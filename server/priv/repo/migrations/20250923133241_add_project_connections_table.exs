defmodule Tuist.Repo.Migrations.AddProjectConnectionsTable do
  use Ecto.Migration

  def change do
    create table(:project_connections) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :provider, :integer, null: false
      add :external_id, :string, null: false
      add :repository_full_handle, :string, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:project_connections, [:project_id, :provider, :external_id])
    create index(:project_connections, [:repository_full_handle])
  end
end
