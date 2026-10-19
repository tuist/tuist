defmodule Tuist.Repo.Migrations.CreateProjectFlyOidcTrustPolicies do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:project_fly_oidc_trust_policies) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :issuer, :string, null: false
      add :organization_id, :string, null: false
      add :application_id, :string, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(
             :project_fly_oidc_trust_policies,
             [:project_id, :issuer, :organization_id, :application_id],
             name: :project_fly_oidc_trust_policies_identity_index,
             concurrently: true
           )

    create index(:project_fly_oidc_trust_policies, [:issuer, :organization_id, :application_id],
             concurrently: true
           )
  end
end
