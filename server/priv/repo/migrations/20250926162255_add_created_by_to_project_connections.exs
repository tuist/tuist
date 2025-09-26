defmodule Tuist.Repo.Migrations.AddCreatedByToProjectConnections do
  use Ecto.Migration

  def change do
    alter table(:project_connections) do
      add :created_by_id, references(:accounts, on_delete: :nilify_all)
    end
  end
end
