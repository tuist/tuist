defmodule Atlas.Repo.Migrations.CreateFinanceInvoices do
  use Ecto.Migration

  def change do
    create table(:finance_invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)

      add :finance_transaction_id,
          references(:finance_transactions, type: :binary_id, on_delete: :nilify_all)

      add :vendor_name, :string, null: false
      add :invoice_number, :string
      add :invoice_date, :date
      add :due_date, :date
      add :period_start, :date
      add :period_end, :date
      add :status, :string, null: false, default: "extracted"
      add :total_amount_value, :decimal, precision: 15, scale: 2
      add :total_amount_currency, :string
      add :tax_amount_value, :decimal, precision: 15, scale: 2
      add :tax_amount_currency, :string
      add :confidence, :decimal, precision: 5, scale: 4
      add :extracted_by_agent, :string
      add :extracted_at, :utc_datetime
      add :last_error, :text
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:finance_invoices, [:document_id], where: "document_id IS NOT NULL")
    create index(:finance_invoices, [:finance_transaction_id])
    create index(:finance_invoices, [:vendor_name])
    create index(:finance_invoices, [:invoice_date])
    create index(:finance_invoices, [:status])

    create table(:finance_invoice_line_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :delete_all), null: false

      add :finance_category_id,
          references(:finance_categories, type: :binary_id, on_delete: :nilify_all)

      add :description, :text, null: false
      add :cost_type, :string
      add :amount_value, :decimal, precision: 15, scale: 2, null: false
      add :amount_currency, :string, null: false
      add :quantity, :decimal, precision: 15, scale: 4
      add :unit_amount_value, :decimal, precision: 15, scale: 4
      add :unit_amount_currency, :string
      add :service_period_start, :date
      add :service_period_end, :date
      add :confidence, :decimal, precision: 5, scale: 4
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:finance_invoice_line_items, [:finance_invoice_id])
    create index(:finance_invoice_line_items, [:finance_category_id])
    create index(:finance_invoice_line_items, [:cost_type])
  end
end
