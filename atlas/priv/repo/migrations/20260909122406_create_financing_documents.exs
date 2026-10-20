defmodule Atlas.Repo.Migrations.CreateFinancingDocuments do
  use Ecto.Migration

  def up do
    alter table(:financings) do
      add :supplier, :string
    end

    create table(:financing_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :financing_id,
          references(:financings, type: :binary_id, on_delete: :delete_all),
          null: false

      add :document_id,
          references(:documents, type: :binary_id, on_delete: :delete_all),
          null: false

      add :kind, :string, null: false
      add :notes, :text

      timestamps()
    end

    create unique_index(:financing_documents, [:financing_id, :document_id, :kind])
    create index(:financing_documents, [:document_id])

    create constraint(:financing_documents, :financing_documents_kind_check,
             check:
               "kind IN ('supplier_contract','financing_agreement','guarantee','invoice','acceptance','schedule','amendment','other')"
           )

    execute("""
    INSERT INTO financing_documents (id, financing_id, document_id, kind, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, contract_document_id, 'financing_agreement', NOW(), NOW()
    FROM financings
    WHERE contract_document_id IS NOT NULL
    """)

    alter table(:financings) do
      remove :contract_document_id
    end
  end

  def down do
    alter table(:financings) do
      add :contract_document_id,
          references(:documents, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:financings, [:contract_document_id])

    execute("""
    UPDATE financings
    SET contract_document_id = source.document_id
    FROM (
      SELECT DISTINCT ON (financing_id) financing_id, document_id
      FROM financing_documents
      WHERE kind = 'financing_agreement'
      ORDER BY financing_id, inserted_at, id
    ) AS source
    WHERE financings.id = source.financing_id
    """)

    drop table(:financing_documents)

    alter table(:financings) do
      remove :supplier
    end
  end
end
