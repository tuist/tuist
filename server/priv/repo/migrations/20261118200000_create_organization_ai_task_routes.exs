defmodule Tuist.Repo.Migrations.CreateOrganizationAiTaskRoutes do
  use Ecto.Migration

  def change do
    create table(:organization_ai_task_routes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :task, :string, null: false

      # The composite key keeps a route on its own organization's model, and
      # removing that model (or its connection) removes the route.
      add :model_id,
          references(:organization_ai_models,
            with: [organization_id: :organization_id],
            on_delete: :delete_all
          ),
          null: false

      timestamps(type: :timestamptz)
    end

    # Both indexes belong to a new, empty table with no existing writers.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:organization_ai_task_routes, [:organization_id, :task])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:organization_ai_task_routes, [:model_id])
  end
end
