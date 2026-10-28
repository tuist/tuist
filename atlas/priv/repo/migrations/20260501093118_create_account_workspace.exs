defmodule Atlas.Repo.Migrations.CreateAccountWorkspace do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_key, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :primary_domain, :string
      add :segment, :string, null: false
      add :currency, :string
      add :current_value, :decimal, precision: 15, scale: 2
      add :next_renewal_date, :date
      add :stripe_customer_id, :string
      add :latest_activity_at, :utc_datetime
      add :contacts_count, :integer, default: 0, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create unique_index(:accounts, [:account_key])

    create index(:accounts, [:segment])
    create index(:accounts, [:latest_activity_at])

    create table(:account_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :full_name, :string, null: false
      add :email, :string, null: false
      add :title, :string
      add :notes, :text

      timestamps()
    end

    create unique_index(:account_contacts, [:account_id, :email])

    create table(:account_handles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :handle, :string, null: false
      add :source, :string, null: false

      timestamps()
    end

    create unique_index(:account_handles, [:handle])
    create index(:account_handles, [:account_id])

    create table(:account_invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :external_id, :string, null: false
      add :source, :string, null: false
      add :due_date, :date, null: false
      add :amount_value, :decimal, precision: 15, scale: 2
      add :amount_currency, :string
      add :status, :string
      add :stripe_url, :string

      timestamps()
    end

    create unique_index(:account_invoices, [:source, :external_id])
    create index(:account_invoices, [:account_id, :due_date])

    create table(:account_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :external_id, :string, null: false
      add :source, :string, null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :occurred_at, :utc_datetime, null: false
      add :url, :string
      add :metadata, :map, default: %{}, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:account_events, [:source, :external_id])
    create index(:account_events, [:account_id, :occurred_at])
    create index(:account_events, [:kind])
    create index(:account_events, [:author_id])
  end
end
