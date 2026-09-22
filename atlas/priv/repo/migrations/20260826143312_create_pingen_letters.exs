defmodule Atlas.Repo.Migrations.CreatePingenLetters do
  use Ecto.Migration

  def change do
    create table(:letters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :confirmed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :recipient_name, :string, null: false
      add :recipient_street, :string, null: false
      add :recipient_postal_code, :string, null: false
      add :recipient_city, :string, null: false
      add :recipient_country, :string, null: false, default: "DE"
      add :recipient_reference, :string
      add :sender_name, :string, null: false
      add :sender_street, :string, null: false
      add :sender_postal_code, :string, null: false
      add :sender_city, :string, null: false
      add :sender_country, :string, null: false, default: "DE"
      add :signatory_name, :string
      add :signatory_title, :string
      add :tax_id, :string
      add :vat_id, :string
      add :subject, :string, null: false
      add :body, :text, null: false
      add :pingen_letter_id, :string
      add :pingen_tracking_number, :string
      add :pingen_status, :string
      add :pingen_events, :map, null: false, default: %{"items" => []}
      add :last_error, :text
      add :confirmed_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :undeliverable_at, :utc_datetime
      add :last_checked_at, :utc_datetime

      timestamps()
    end

    create index(:letters, [:account_id, :inserted_at])
    create index(:letters, [:status, :last_checked_at])
    create index(:letters, [:document_id])
    create index(:letters, [:created_by_id])
    create unique_index(:letters, [:pingen_letter_id], where: "pingen_letter_id IS NOT NULL")

    create constraint(:letters, :letters_kind_check, check: "kind IN ('tax_certificate_request')")

    create constraint(:letters, :letters_status_check,
             check:
               "status IN ('queued', 'sending', 'sent', 'delivered', 'undeliverable', 'failed')"
           )
  end
end
