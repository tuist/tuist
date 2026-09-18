defmodule Atlas.Repo.Migrations.CreateInsurance do
  use Ecto.Migration

  def change do
    create table(:insurance_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider, :string, null: false
      add :product, :string, null: false
      add :reference, :string

      add :currency, :string, null: false
      add :sum_insured, :decimal, precision: 15, scale: 2, null: false
      add :provisional_cover_pct, :integer, null: false, default: 0

      add :annual_premium, :decimal, precision: 15, scale: 2, null: false, default: 0
      add :premium_frequency, :string, null: false, default: "annual"

      add :deductible_per_claim, :decimal, precision: 15, scale: 2, null: false, default: 0
      add :deductible_cap, :decimal, precision: 15, scale: 2

      add :mobile_use_pct, :integer, null: false, default: 0

      add :cleanup_pct, :integer, null: false, default: 0
      add :cleanup_min, :decimal, precision: 15, scale: 2
      add :cleanup_max, :decimal, precision: 15, scale: 2

      add :movement_pct, :integer, null: false, default: 0
      add :movement_min, :decimal, precision: 15, scale: 2
      add :movement_max, :decimal, precision: 15, scale: 2

      add :covers_data, :boolean, null: false, default: false
      add :covers_software, :boolean, null: false, default: false
      add :covers_dongles, :boolean, null: false, default: false
      add :covers_leased, :boolean, null: false, default: false
      add :covers_third_party_owned, :boolean, null: false, default: false

      add :starts_on, :date
      add :ends_on, :date
      add :quote_valid_until, :date

      add :status, :string, null: false, default: "quoted"

      add :contract_document_id,
          references(:documents, type: :binary_id, on_delete: :nilify_all)

      add :previous_policy_id,
          references(:insurance_policies, type: :binary_id, on_delete: :nilify_all)

      add :notes, :text

      timestamps()
    end

    create index(:insurance_policies, [:status])
    create index(:insurance_policies, [:provider])
    create index(:insurance_policies, [:contract_document_id])
    create index(:insurance_policies, [:previous_policy_id])

    create constraint(:insurance_policies, :insurance_policies_status_check,
             check: "status IN ('quoted','active','expired','cancelled','terminated')"
           )

    create constraint(:insurance_policies, :insurance_policies_frequency_check,
             check: "premium_frequency IN ('annual','quarterly','monthly')"
           )

    create constraint(:insurance_policies, :insurance_policies_sum_insured_nonneg,
             check: "sum_insured >= 0"
           )

    create constraint(:insurance_policies, :insurance_policies_provisional_cover_pct_range,
             check: "provisional_cover_pct BETWEEN 0 AND 200"
           )

    create constraint(:insurance_policies, :insurance_policies_mobile_use_pct_range,
             check: "mobile_use_pct BETWEEN 0 AND 100"
           )

    create constraint(:insurance_policies, :insurance_policies_cleanup_pct_range,
             check: "cleanup_pct BETWEEN 0 AND 100"
           )

    create constraint(:insurance_policies, :insurance_policies_movement_pct_range,
             check: "movement_pct BETWEEN 0 AND 100"
           )

    create constraint(:insurance_policies, :insurance_policies_annual_premium_nonneg,
             check: "annual_premium >= 0"
           )

    create constraint(:insurance_policies, :insurance_policies_deductible_per_claim_nonneg,
             check: "deductible_per_claim >= 0"
           )

    create constraint(:insurance_policies, :insurance_policies_deductible_cap_nonneg,
             check: "deductible_cap IS NULL OR deductible_cap >= 0"
           )

    create constraint(:insurance_policies, :insurance_policies_dates_ordered,
             check: "ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on"
           )

    create constraint(:insurance_policies, :insurance_policies_cleanup_min_max,
             check: "cleanup_min IS NULL OR cleanup_max IS NULL OR cleanup_max >= cleanup_min"
           )

    create constraint(:insurance_policies, :insurance_policies_movement_min_max,
             check: "movement_min IS NULL OR movement_max IS NULL OR movement_max >= movement_min"
           )

    create table(:insurance_policy_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :policy_id,
          references(:insurance_policies, type: :binary_id, on_delete: :restrict),
          null: false

      add :asset_id,
          references(:assets, type: :binary_id, on_delete: :restrict),
          null: false

      add :declared_value, :decimal, precision: 15, scale: 2, null: false
      add :covered_from, :date, null: false
      add :covered_to, :date

      add :notes, :text

      timestamps()
    end

    create index(:insurance_policy_members, [:policy_id])
    create index(:insurance_policy_members, [:asset_id])

    create unique_index(:insurance_policy_members, [:policy_id, :asset_id],
             where: "covered_to IS NULL",
             name: :insurance_policy_members_open_per_asset_per_policy_index
           )

    create constraint(:insurance_policy_members, :insurance_policy_members_declared_value_nonneg,
             check: "declared_value >= 0"
           )

    create constraint(:insurance_policy_members, :insurance_policy_members_dates_ordered,
             check: "covered_to IS NULL OR covered_to >= covered_from"
           )

    create table(:insurance_claims, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :policy_id,
          references(:insurance_policies, type: :binary_id, on_delete: :restrict),
          null: false

      add :claim_reference, :string

      add :incident_on, :date, null: false
      add :incident_type, :string, null: false

      add :reported_on, :date
      add :status, :string, null: false, default: "draft"

      add :claimed_amount, :decimal, precision: 15, scale: 2
      add :payout_amount, :decimal, precision: 15, scale: 2
      add :deductible_applied, :decimal, precision: 15, scale: 2

      add :notes, :text

      timestamps()
    end

    create index(:insurance_claims, [:policy_id])
    create index(:insurance_claims, [:status])
    create index(:insurance_claims, [:incident_on])

    create constraint(:insurance_claims, :insurance_claims_status_check,
             check: "status IN ('draft','submitted','approved','paid','rejected','withdrawn')"
           )

    create constraint(:insurance_claims, :insurance_claims_incident_type_check,
             check: "incident_type IN ('theft','damage','fire','water','loss','other')"
           )

    create constraint(:insurance_claims, :insurance_claims_amounts_nonneg,
             check:
               "(claimed_amount IS NULL OR claimed_amount >= 0) AND (payout_amount IS NULL OR payout_amount >= 0) AND (deductible_applied IS NULL OR deductible_applied >= 0)"
           )

    create constraint(:insurance_claims, :insurance_claims_reported_after_incident,
             check: "reported_on IS NULL OR reported_on >= incident_on"
           )

    create table(:insurance_claim_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :claim_id,
          references(:insurance_claims, type: :binary_id, on_delete: :restrict),
          null: false

      add :asset_id,
          references(:assets, type: :binary_id, on_delete: :restrict),
          null: false

      add :damage_amount, :decimal, precision: 15, scale: 2
      add :notes, :text

      timestamps()
    end

    create index(:insurance_claim_assets, [:claim_id])
    create index(:insurance_claim_assets, [:asset_id])
    create unique_index(:insurance_claim_assets, [:claim_id, :asset_id])

    create constraint(:insurance_claim_assets, :insurance_claim_assets_damage_nonneg,
             check: "damage_amount IS NULL OR damage_amount >= 0"
           )
  end
end
