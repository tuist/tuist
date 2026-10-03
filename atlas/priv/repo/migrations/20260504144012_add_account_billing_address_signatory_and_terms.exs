defmodule Atlas.Repo.Migrations.AddAccountBillingAddressSignatoryAndTerms do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :url, :string
      add :legal_name, :string
      add :contract_id, :string
      add :status, :string
      add :churned_date, :date
      add :churn_reason, :text

      add :address, :map
      add :billing, :map
      add :signatory, :map
    end

    create table(:account_terms, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :external_id, :string
      add :source, :string, null: false

      add :payment, :string, null: false
      add :start_date, :date, null: false
      add :end_date, :date
      add :price_per_seat, :decimal, precision: 15, scale: 2
      add :seats, :integer
      add :discount, :decimal, precision: 15, scale: 2
      add :total, :decimal, precision: 15, scale: 2, null: false
      add :currency, :string
      add :on_premise, :boolean, default: false, null: false
      add :renewal_notice_weeks, :integer
      add :po_number, :string

      timestamps()
    end

    create index(:account_terms, [:account_id, :start_date])
    create unique_index(:account_terms, [:source, :external_id], where: "external_id IS NOT NULL")
  end
end
