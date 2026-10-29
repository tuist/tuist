defmodule Atlas.Repo.Migrations.CreateFinanceFinancings do
  use Ecto.Migration

  def change do
    create table(:financings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :type, :string, null: false
      add :accounting_treatment, :string, null: false, default: "undetermined"
      add :treatment_evidence, :text

      add :provider, :string, null: false
      add :reference, :string
      add :disbursement_or_commencement_on, :date, null: false
      add :term_months, :integer
      add :currency, :string, null: false

      add :undiscounted_commitment, :decimal, precision: 15, scale: 2, null: false, default: 0
      add :initial_liability, :decimal, precision: 15, scale: 2
      add :interest_rate, :decimal, precision: 7, scale: 4

      add :principal_amount, :decimal, precision: 15, scale: 2

      add :purchase_option_amount, :decimal, precision: 15, scale: 2
      add :purchase_option_available_from, :date

      add :status, :string, null: false, default: "active"

      add :contract_document_id,
          references(:documents, type: :binary_id, on_delete: :nilify_all)

      add :notes, :text

      timestamps()
    end

    create index(:financings, [:type])
    create index(:financings, [:status])
    create index(:financings, [:provider])
    create index(:financings, [:contract_document_id])

    create constraint(:financings, :financings_type_check,
             check:
               "type IN ('loan','lease_with_purchase_option','lease_without_purchase_option')"
           )

    create constraint(:financings, :financings_treatment_check,
             check: "accounting_treatment IN ('capitalized','expensed','undetermined')"
           )

    create constraint(:financings, :financings_status_check,
             check: "status IN ('active','paid_off','option_exercised','returned','terminated')"
           )

    create constraint(:financings, :financings_term_positive,
             check: "term_months IS NULL OR term_months > 0"
           )

    create constraint(:financings, :financings_undiscounted_nonneg,
             check: "undiscounted_commitment >= 0"
           )

    create constraint(:financings, :financings_initial_liability_nonneg,
             check: "initial_liability IS NULL OR initial_liability >= 0"
           )

    create constraint(:financings, :financings_principal_nonneg,
             check: "principal_amount IS NULL OR principal_amount >= 0"
           )

    create constraint(:financings, :financings_option_amount_nonneg,
             check: "purchase_option_amount IS NULL OR purchase_option_amount >= 0"
           )

    create constraint(:financings, :financings_principal_iff_loan,
             check:
               "(type = 'loan' AND principal_amount IS NOT NULL) OR (type <> 'loan' AND principal_amount IS NULL)"
           )

    create constraint(:financings, :financings_option_amount_iff_option_lease,
             check: "purchase_option_amount IS NULL OR type = 'lease_with_purchase_option'"
           )

    create constraint(:financings, :financings_status_option_exercised_iff_option_lease,
             check: "status <> 'option_exercised' OR type = 'lease_with_purchase_option'"
           )

    create constraint(:financings, :financings_status_returned_iff_lease,
             check: "status <> 'returned' OR type <> 'loan'"
           )

    create table(:financing_schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :financing_id,
          references(:financings, type: :binary_id, on_delete: :restrict),
          null: false

      add :sequence, :integer, null: false
      add :due_on, :date, null: false

      add :expected_total, :decimal, precision: 15, scale: 2, null: false

      add :principal_amount, :decimal, precision: 15, scale: 2
      add :interest_amount, :decimal, precision: 15, scale: 2
      add :rental_amount, :decimal, precision: 15, scale: 2
      add :fee_amount, :decimal, precision: 15, scale: 2
      add :tax_amount, :decimal, precision: 15, scale: 2
      add :option_amount, :decimal, precision: 15, scale: 2
      add :deposit_amount, :decimal, precision: 15, scale: 2

      add :notes, :text

      timestamps()
    end

    create unique_index(:financing_schedules, [:financing_id, :sequence])
    create unique_index(:financing_schedules, [:financing_id, :id])

    for field <- [
          :principal_amount,
          :interest_amount,
          :rental_amount,
          :fee_amount,
          :tax_amount,
          :option_amount,
          :deposit_amount
        ] do
      create constraint(:financing_schedules, :"financing_schedules_#{field}_nonneg",
               check: "#{field} IS NULL OR #{field} >= 0"
             )
    end

    create constraint(:financing_schedules, :financing_schedules_expected_total_nonneg,
             check: "expected_total >= 0"
           )

    create constraint(:financing_schedules, :financing_schedules_components_bounded,
             check: """
             COALESCE(principal_amount,0) + COALESCE(interest_amount,0) +
             COALESCE(rental_amount,0) + COALESCE(fee_amount,0) +
             COALESCE(tax_amount,0) + COALESCE(option_amount,0) +
             COALESCE(deposit_amount,0) <= expected_total
             """
           )

    create table(:financing_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :financing_id,
          references(:financings, type: :binary_id, on_delete: :restrict),
          null: false

      add :asset_id, references(:assets, type: :binary_id, on_delete: :restrict), null: false

      add :share_bps, :integer, null: false
      add :notes, :text

      timestamps()
    end

    create unique_index(:financing_lines, [:financing_id, :asset_id])
    create index(:financing_lines, [:asset_id])

    create constraint(:financing_lines, :financing_lines_share_bps_range,
             check: "share_bps BETWEEN 1 AND 10000"
           )

    create table(:financing_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :financing_id,
          references(:financings, type: :binary_id, on_delete: :restrict),
          null: false

      add :finance_transaction_id,
          references(:finance_transactions, type: :binary_id, on_delete: :restrict),
          null: false

      add :schedule_id, :binary_id

      add :paid_on, :date, null: false
      add :direction, :string, null: false

      add :settlement_amount, :decimal, precision: 15, scale: 2, null: false
      add :settlement_currency, :string, null: false

      add :principal_amount, :decimal, precision: 15, scale: 2
      add :interest_amount, :decimal, precision: 15, scale: 2
      add :rental_amount, :decimal, precision: 15, scale: 2
      add :fee_amount, :decimal, precision: 15, scale: 2
      add :tax_amount, :decimal, precision: 15, scale: 2
      add :option_amount, :decimal, precision: 15, scale: 2
      add :deposit_amount, :decimal, precision: 15, scale: 2
      add :unclassified_amount, :decimal, precision: 15, scale: 2

      add :resolution_status, :string, null: false, default: "unresolved"

      add :notes, :text

      timestamps()
    end

    create unique_index(:financing_payments, [:finance_transaction_id])
    create index(:financing_payments, [:financing_id])
    create index(:financing_payments, [:schedule_id])

    # Composite FK on (financing_id, schedule_id) referencing the composite
    # UNIQUE on financing_schedules(financing_id, id). Uses MATCH SIMPLE so
    # a null schedule_id is permitted (unresolved-schedule payments).
    execute(
      """
      ALTER TABLE financing_payments
      ADD CONSTRAINT financing_payments_schedule_fk
      FOREIGN KEY (financing_id, schedule_id)
      REFERENCES financing_schedules (financing_id, id)
      MATCH SIMPLE
      """,
      "ALTER TABLE financing_payments DROP CONSTRAINT financing_payments_schedule_fk"
    )

    create constraint(:financing_payments, :financing_payments_direction_check,
             check: "direction IN ('debit','credit')"
           )

    create constraint(:financing_payments, :financing_payments_resolution_status_check,
             check: "resolution_status IN ('resolved','unresolved','partial')"
           )

    create constraint(:financing_payments, :financing_payments_settlement_nonneg,
             check: "settlement_amount >= 0"
           )

    for field <- [
          :principal_amount,
          :interest_amount,
          :rental_amount,
          :fee_amount,
          :tax_amount,
          :option_amount,
          :deposit_amount,
          :unclassified_amount
        ] do
      create constraint(:financing_payments, :"financing_payments_#{field}_nonneg",
               check: "#{field} IS NULL OR #{field} >= 0"
             )
    end

    create constraint(:financing_payments, :financing_payments_components_bounded,
             check: """
             COALESCE(principal_amount,0) + COALESCE(interest_amount,0) +
             COALESCE(rental_amount,0) + COALESCE(fee_amount,0) +
             COALESCE(tax_amount,0) + COALESCE(option_amount,0) +
             COALESCE(deposit_amount,0) + COALESCE(unclassified_amount,0)
             <= settlement_amount
             """
           )

    create constraint(:financing_payments, :financing_payments_resolved_reconciles,
             check: """
             resolution_status <> 'resolved' OR (
               COALESCE(principal_amount,0) + COALESCE(interest_amount,0) +
               COALESCE(rental_amount,0) + COALESCE(fee_amount,0) +
               COALESCE(tax_amount,0) + COALESCE(option_amount,0) +
               COALESCE(deposit_amount,0) = settlement_amount
               AND COALESCE(unclassified_amount,0) = 0
             )
             """
           )
  end
end
