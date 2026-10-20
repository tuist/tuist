defmodule Atlas.Repo.Migrations.ClearInvoiceDocumentAccounts do
  use Ecto.Migration

  def up do
    execute """
    UPDATE documents
    SET account_id = NULL,
        updated_at = NOW()
    WHERE source = 'qonto'
      AND account_id IS NOT NULL
      AND (attributes ? 'qonto_transaction_id' OR attributes ? 'qonto_attachment_id')
    """

    execute """
    UPDATE documents
    SET account_id = NULL,
        updated_at = NOW()
    WHERE account_id IS NOT NULL
      AND (
        lower(coalesce(title, '')) LIKE '%invoice%'
        OR lower(coalesce(original_filename, '')) LIKE '%invoice%'
        OR EXISTS (
          SELECT 1
          FROM document_types
          WHERE document_types.id = documents.document_type_id
            AND lower(document_types.name) LIKE '%invoice%'
        )
      )
    """
  end

  def down, do: :ok
end
