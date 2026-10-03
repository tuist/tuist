defmodule Atlas.Repo.Migrations.AddTaxCertificateSignatureWorkflowToLetters do
  use Ecto.Migration

  def up do
    alter table(:letters) do
      add :signed_document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)
      add :signed_uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :signed_uploaded_at, :utc_datetime
      add :template_data, :map, null: false, default: %{}
      modify :status, :string, null: false, default: "awaiting_signature"
      modify :confirmed_at, :utc_datetime, null: true
    end

    create index(:letters, [:signed_document_id])
    create index(:letters, [:signed_uploaded_by_id])

    drop constraint(:letters, :letters_status_check)

    create constraint(:letters, :letters_status_check,
             check:
               "status IN ('awaiting_signature', 'awaiting_delivery_confirmation', 'queued', 'sending', 'sent', 'delivered', 'undeliverable', 'failed')"
           )
  end

  def down do
    drop constraint(:letters, :letters_status_check)

    create constraint(:letters, :letters_status_check,
             check:
               "status IN ('queued', 'sending', 'sent', 'delivered', 'undeliverable', 'failed')"
           )

    drop index(:letters, [:signed_document_id])
    drop index(:letters, [:signed_uploaded_by_id])

    alter table(:letters) do
      remove :signed_document_id
      remove :signed_uploaded_by_id
      remove :signed_uploaded_at
      remove :template_data
      modify :status, :string, null: false, default: "queued"
      modify :confirmed_at, :utc_datetime, null: false
    end
  end
end
