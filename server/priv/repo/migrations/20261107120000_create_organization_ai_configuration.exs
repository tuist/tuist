defmodule Tuist.Repo.Migrations.CreateOrganizationAiConfiguration do
  use Ecto.Migration

  def change do
    create table(:organization_ai_connections) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :base_url, :text, null: false
      add :api_key, :binary, null: false
      timestamps(type: :timestamptz)
    end

    # All indexes below belong to new, empty tables, with no existing writers.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:organization_ai_connections, [:id, :organization_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:organization_ai_connections, [:organization_id])

    create table(:organization_ai_models) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :connection_id,
          references(:organization_ai_connections,
            with: [organization_id: :organization_id],
            on_delete: :delete_all
          ),
          null: false

      add :name, :string, null: false
      add :model_id, :string, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:organization_ai_models, [:connection_id, :model_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:organization_ai_models, [:id, :organization_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:organization_ai_models, [:organization_id])

    create table(:organization_ai_defaults) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :model_id,
          references(:organization_ai_models,
            with: [organization_id: :organization_id],
            on_delete: :delete_all
          ),
          null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:organization_ai_defaults, [:organization_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:organization_ai_defaults, [:model_id])
  end
end
