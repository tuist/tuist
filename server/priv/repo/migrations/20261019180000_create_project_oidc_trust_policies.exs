defmodule Tuist.Repo.Migrations.CreateProjectOidcTrustPolicies do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:project_oidc_trust_policies) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :issuer, :text, null: false
      add :jwks_url, :text, null: false
      add :audience, :string, null: false
      add :claims, :map, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:project_oidc_trust_policies, [:project_id, :name], concurrently: true)

    create index(:project_oidc_trust_policies, [:issuer], concurrently: true)
  end
end
