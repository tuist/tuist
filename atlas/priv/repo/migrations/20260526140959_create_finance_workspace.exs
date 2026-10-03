defmodule Atlas.Repo.Migrations.CreateFinanceWorkspace do
  use Ecto.Migration

  def change do
    create table(:finance_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :config_key, :string, null: false
      add :name, :string, null: false
      add :external_id, :string
      add :last_synced_at, :utc_datetime
      add :last_successful_sync_at, :utc_datetime
      add :last_error, :text
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:finance_sources, [:config_key])
    create index(:finance_sources, [:provider])

    create table(:finance_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :finance_source_id,
          references(:finance_sources, type: :binary_id, on_delete: :delete_all), null: false

      add :provider, :string, null: false
      add :external_id, :string, null: false
      add :name, :string, null: false
      add :account_type, :string
      add :account_subtype, :string
      add :currency, :string
      add :iban, :string
      add :bic, :string
      add :main, :boolean, null: false, default: false
      add :status, :string
      add :balance_value, :decimal, precision: 15, scale: 2
      add :balance_currency, :string
      add :available_balance_value, :decimal, precision: 15, scale: 2
      add :available_balance_currency, :string
      add :transactions_synced_at, :utc_datetime
      add :refreshed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:finance_accounts, [:finance_source_id, :external_id])
    create index(:finance_accounts, [:provider])
    create index(:finance_accounts, [:currency])
    create index(:finance_accounts, [:transactions_synced_at])

    create table(:finance_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :finance_account_id,
          references(:finance_accounts, type: :binary_id, on_delete: :delete_all), null: false

      add :provider, :string, null: false
      add :external_id, :string, null: false
      add :status, :string
      add :direction, :string, null: false
      add :kind, :string
      add :counterparty_name, :string
      add :description, :text
      add :reference, :string
      add :amount_value, :decimal, precision: 15, scale: 2, null: false
      add :amount_currency, :string, null: false
      add :local_amount_value, :decimal, precision: 15, scale: 2
      add :local_amount_currency, :string
      add :fee_value, :decimal, precision: 15, scale: 2
      add :fee_currency, :string
      add :running_balance_value, :decimal, precision: 15, scale: 2
      add :running_balance_currency, :string
      add :booked_at, :utc_datetime
      add :settled_at, :utc_datetime
      add :provider_updated_at, :utc_datetime
      add :affects_cash_balance, :boolean, null: false, default: true
      add :affects_runway, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}
      add :raw, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create unique_index(:finance_transactions, [:finance_account_id, :external_id])
    create index(:finance_transactions, [:provider])
    create index(:finance_transactions, [:booked_at])
    create index(:finance_transactions, [:settled_at])
    create index(:finance_transactions, [:direction])
    create index(:finance_transactions, [:kind])

    create table(:finance_sync_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :finance_source_id,
          references(:finance_sources, type: :binary_id, on_delete: :delete_all), null: false

      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :accounts_seen, :integer, null: false, default: 0
      add :transactions_seen, :integer, null: false, default: 0
      add :error, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create index(:finance_sync_runs, [:finance_source_id, :started_at])
  end
end
