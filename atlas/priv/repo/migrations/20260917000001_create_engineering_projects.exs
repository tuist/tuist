defmodule Atlas.Repo.Migrations.CreateEngineeringProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :timestamptz)
    end

    create unique_index(:projects, [:name])

    create table(:github_repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner, :string, null: false
      add :name, :string, null: false
      add :visibility, :string, null: false, default: "public"
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create unique_index(:github_repositories, [:owner, :name])
    create index(:github_repositories, [:project_id])

    create table(:project_webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :source, :string, null: false
      add :token_hash, :string, null: false
      add :last_used_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:project_webhooks, [:token_hash])
    create index(:project_webhooks, [:project_id])
  end
end
