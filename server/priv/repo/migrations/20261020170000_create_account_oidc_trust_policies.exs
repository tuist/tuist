defmodule Tuist.Repo.Migrations.CreateAccountOidcTrustPolicies do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:account_oidc_trust_policies) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :issuer, :text, null: false
      add :jwks_url, :text, null: false
      add :audience, :string, null: false
      add :claims, :map, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:account_oidc_trust_policies, [:account_id, :name], concurrently: true)
    create index(:account_oidc_trust_policies, [:issuer], concurrently: true)
  end
end
