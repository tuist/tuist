defmodule Atlas.Repo.Migrations.CreateEngineeringDomains do
  use Ecto.Migration

  def change do
    create table(:domains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :timestamptz)
    end

    create unique_index(:domains, [:name])

    create table(:projects_domains, primary_key: false) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :timestamptz)
    end

    create index(:projects_domains, [:domain_id])
  end
end
