defmodule Atlas.Repo.Migrations.CreateCrossDomainClaims do
  use Ecto.Migration

  def change do
    create table(:cross_domain_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :claim_kind, :string, null: false
      add :domains, {:array, :string}, null: false

      add :subject_account_id,
          references(:accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :version, :integer, null: false, default: 1

      add :superseded_by_id,
          references(:cross_domain_claims, type: :binary_id, on_delete: :nilify_all)

      add :statement, :text, null: false
      add :confidence, :decimal, precision: 5, scale: 4, null: false
      add :sensitivity, :string, null: false
      add :link_precision, :string, null: false
      add :link_basis, :string, null: false
      add :generated_by_agent, :string, null: false
      add :valid_from, :utc_datetime, null: false
      add :valid_until, :utc_datetime

      timestamps()
    end

    create unique_index(:cross_domain_claims, [:claim_kind, :subject_account_id, :version])

    create index(:cross_domain_claims, [:subject_account_id],
             where: "superseded_by_id IS NULL",
             name: :cross_domain_claims_current_index
           )

    create constraint(:cross_domain_claims, :cross_domain_claims_kind_check,
             check:
               "claim_kind IN ('account_engagement_gap', 'account_delivery_dependency', 'account_renewal_exposure')"
           )

    create constraint(:cross_domain_claims, :cross_domain_claims_domains_check,
             check:
               "cardinality(domains) >= 2 AND domains <@ ARRAY['finance', 'accounts', 'outreach', 'product', 'company']::varchar[]"
           )

    create constraint(:cross_domain_claims, :cross_domain_claims_precision_check,
             check: "link_precision IN ('exact', 'verified')"
           )

    create constraint(:cross_domain_claims, :cross_domain_claims_confidence_check,
             check: "confidence >= 0.80 AND confidence <= 1"
           )

    create constraint(:cross_domain_claims, :cross_domain_claims_sensitivity_check,
             check: "sensitivity IN ('public', 'internal', 'restricted')"
           )
  end
end
