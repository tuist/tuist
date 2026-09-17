defmodule Atlas.Repo.Migrations.CreateInsuranceDocuments do
  use Ecto.Migration

  def up do
    # Replace the single `contract_document_id` pointer with a proper join so
    # a policy can carry the quote, the bound policy, the AVB terms, and any
    # subsequent renewals or endorsements without collision.
    alter table(:insurance_policies) do
      remove :contract_document_id
    end

    create table(:insurance_policy_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :policy_id,
          references(:insurance_policies, type: :binary_id, on_delete: :restrict),
          null: false

      add :document_id,
          references(:documents, type: :binary_id, on_delete: :restrict),
          null: false

      add :kind, :string, null: false, default: "other"
      add :notes, :text

      timestamps()
    end

    create index(:insurance_policy_documents, [:policy_id])
    create index(:insurance_policy_documents, [:document_id])
    create unique_index(:insurance_policy_documents, [:policy_id, :document_id, :kind])

    create constraint(:insurance_policy_documents, :insurance_policy_documents_kind_check,
             check: "kind IN ('quote','policy','avb','renewal','endorsement','other')"
           )

    create table(:insurance_claim_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :claim_id,
          references(:insurance_claims, type: :binary_id, on_delete: :restrict),
          null: false

      add :document_id,
          references(:documents, type: :binary_id, on_delete: :restrict),
          null: false

      add :kind, :string, null: false, default: "other"
      add :notes, :text

      timestamps()
    end

    create index(:insurance_claim_documents, [:claim_id])
    create index(:insurance_claim_documents, [:document_id])
    create unique_index(:insurance_claim_documents, [:claim_id, :document_id, :kind])

    create constraint(:insurance_claim_documents, :insurance_claim_documents_kind_check,
             check: "kind IN ('photo','insurer_correspondence','repair_invoice','report','other')"
           )
  end

  def down do
    drop table(:insurance_claim_documents)
    drop table(:insurance_policy_documents)

    alter table(:insurance_policies) do
      add :contract_document_id,
          references(:documents, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
