defmodule Atlas.Repo.Migrations.CreateAssets do
  use Ecto.Migration

  def change do
    create table(:assets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_tag, :string
      add :serial_number, :string
      add :manufacturer, :string
      add :model, :string
      add :name, :string, null: false

      add :category, :string, null: false
      add :specs, :map, null: false, default: %{}

      add :purchased_on, :date, null: false
      add :placed_in_service_on, :date
      add :acquisition_cost, :decimal, precision: 15, scale: 2, null: false
      add :acquisition_currency, :string, null: false
      add :useful_life_months, :integer, null: false
      add :salvage_value, :decimal, precision: 15, scale: 2, null: false, default: 0
      add :valuation_treatment, :string, null: false, default: "depreciable"

      add :state, :string, null: false, default: "in_storage"
      add :location, :string, null: false, default: "office"
      add :location_detail, :string
      add :warranty_end_on, :date

      add :assigned_to_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :rack_position, :map

      add :finance_transaction_id,
          references(:finance_transactions, type: :binary_id, on_delete: :nilify_all)

      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)

      add :purchase_document_id,
          references(:documents, type: :binary_id, on_delete: :nilify_all)

      add :vendor, :string

      add :pre_loss_state, :string
      add :pre_repair_state, :string

      add :lost_on, :date
      add :recovered_on, :date
      add :retired_on, :date
      add :disposed_on, :date
      add :disposal_proceeds, :decimal, precision: 15, scale: 2
      add :disposal_currency, :string

      add :notes, :text

      timestamps()
    end

    create unique_index(:assets, [:asset_tag],
             where: "asset_tag IS NOT NULL",
             name: :assets_asset_tag_index
           )

    create unique_index(:assets, [:manufacturer, :serial_number],
             where: "serial_number IS NOT NULL",
             name: :assets_serial_number_index
           )

    create index(:assets, [:assigned_to_id])
    create index(:assets, [:state])
    create index(:assets, [:category])
    create index(:assets, [:location])
    create index(:assets, [:finance_transaction_id])
    create index(:assets, [:finance_invoice_id])
    create index(:assets, [:purchase_document_id])
    create index(:assets, [:warranty_end_on])

    create constraint(:assets, :assets_category_check,
             check:
               "category IN ('laptop','desktop','server','network_switch','router','ups','monitor','peripheral','other')"
           )

    create constraint(:assets, :assets_state_check,
             check: "state IN ('in_service','in_storage','in_repair','retired','disposed','lost')"
           )

    create constraint(:assets, :assets_location_check,
             check: "location IN ('data_center','office','home','in_transit','other')"
           )

    create constraint(:assets, :assets_valuation_treatment_check,
             check: "valuation_treatment IN ('depreciable','fully_expensed','unknown')"
           )

    create constraint(:assets, :assets_pre_loss_state_check,
             check:
               "pre_loss_state IS NULL OR pre_loss_state IN ('in_service','in_storage','in_repair')"
           )

    create constraint(:assets, :assets_pre_repair_state_check,
             check: "pre_repair_state IS NULL OR pre_repair_state IN ('in_service','in_storage')"
           )

    create constraint(:assets, :assets_useful_life_positive, check: "useful_life_months > 0")

    create constraint(:assets, :assets_acquisition_cost_nonneg, check: "acquisition_cost >= 0")

    create constraint(:assets, :assets_salvage_nonneg, check: "salvage_value >= 0")

    create constraint(:assets, :assets_salvage_bounded,
             check: "salvage_value <= acquisition_cost"
           )

    create constraint(:assets, :assets_serial_manufacturer_present,
             check: "serial_number IS NULL OR manufacturer IS NOT NULL"
           )

    create constraint(:assets, :assets_disposal_currency_when_proceeds,
             check: "disposal_proceeds IS NULL OR disposal_currency IS NOT NULL"
           )

    create constraint(:assets, :assets_retired_state_has_date,
             check: "(state IN ('retired','disposed')) = (retired_on IS NOT NULL)"
           )

    create constraint(:assets, :assets_disposed_state_has_date,
             check: "(state = 'disposed') = (disposed_on IS NOT NULL)"
           )

    create constraint(:assets, :assets_disposal_after_retirement,
             check:
               "disposed_on IS NULL OR (retired_on IS NOT NULL AND disposed_on >= retired_on)"
           )

    create constraint(:assets, :assets_in_service_has_place_date,
             check: "state <> 'in_service' OR placed_in_service_on IS NOT NULL"
           )

    create constraint(:assets, :assets_recovered_after_lost,
             check: "recovered_on IS NULL OR (lost_on IS NOT NULL AND recovered_on >= lost_on)"
           )

    create table(:asset_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_id, references(:assets, type: :binary_id, on_delete: :restrict), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :user_label_snapshot, :string, null: false
      add :assigned_on, :date, null: false
      add :returned_on, :date
      add :notes, :text

      timestamps()
    end

    create index(:asset_assignments, [:asset_id])
    create index(:asset_assignments, [:user_id])

    create unique_index(:asset_assignments, [:asset_id],
             where: "returned_on IS NULL",
             name: :asset_assignments_open_per_asset_index
           )

    create constraint(:asset_assignments, :asset_assignments_returned_after_assigned,
             check: "returned_on IS NULL OR returned_on >= assigned_on"
           )

    create table(:asset_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :asset_id, references(:assets, type: :binary_id, on_delete: :restrict), null: false

      add :event_type, :string, null: false
      add :occurred_on, :date, null: false
      add :notes, :text

      add :expenditure, :decimal, precision: 15, scale: 2
      add :expenditure_currency, :string

      add :finance_transaction_id,
          references(:finance_transactions, type: :binary_id, on_delete: :nilify_all)

      add :previous_warranty_end_on, :date
      add :new_warranty_end_on, :date

      add :client_reference, :string

      timestamps()
    end

    create index(:asset_events, [:asset_id, :occurred_on])
    create index(:asset_events, [:event_type])
    create index(:asset_events, [:finance_transaction_id])

    create unique_index(:asset_events, [:asset_id, :client_reference],
             where: "client_reference IS NOT NULL",
             name: :asset_events_client_reference_index
           )

    create constraint(:asset_events, :asset_events_event_type_check,
             check: "event_type IN ('repaired','warranty_extended','incident','note')"
           )

    create constraint(:asset_events, :asset_events_expenditure_currency_when_amount,
             check: "expenditure IS NULL OR expenditure_currency IS NOT NULL"
           )

    create constraint(:asset_events, :asset_events_warranty_ext_dates,
             check:
               "event_type <> 'warranty_extended' OR (previous_warranty_end_on IS NOT NULL AND new_warranty_end_on IS NOT NULL AND new_warranty_end_on >= previous_warranty_end_on)"
           )
  end
end
