defmodule Tuist.Repo.Migrations.CreateOIDCProjectProviders do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:oidc_project_providers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :last_exchanged_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:oidc_project_providers, [:project_id, :provider])
  end
end
