defmodule Atlas.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :title, :string
      add :description, :string

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :current_deploy_id, :binary_id

      timestamps(type: :timestamptz)
    end

    create unique_index(:pages, [:slug])
    create index(:pages, [:created_by_user_id])

    create table(:page_deploys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :page_id, references(:pages, type: :binary_id, on_delete: :delete_all), null: false

      add :uploaded_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :state, :string, null: false, default: "pending"
      add :file_count, :integer, null: false, default: 0
      add :total_bytes, :bigint, null: false, default: 0
      add :manifest, :jsonb, null: false, default: "[]"
      add :finalized_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:page_deploys, [:page_id])
    create index(:page_deploys, [:uploaded_by_user_id])
    create index(:page_deploys, [:state])

    alter table(:pages) do
      modify :current_deploy_id,
             references(:page_deploys, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
