defmodule Atlas.MCP.Tools.FinanceAddTransactionAttachmentTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tools.FinanceAddTransactionAttachment

  test "passes the configured source map to the provider" do
    source = %{key: "qonto-main", provider: :qonto, name: "Qonto Main"}
    document = insert_document!()
    assert {:ok, _result} = Storage.put_object(document.storage_key, "receipt contents")

    expect(Config, :fetch_source, fn "qonto-main" -> {:ok, source} end)

    expect(Qonto, :add_attachment, fn ^source, "transaction-1", "receipt contents", "receipt.pdf", "application/pdf" ->
      {:ok, %{"id" => "attachment-1"}}
    end)

    assert {:ok, result} =
             execute_tool(FinanceAddTransactionAttachment, executive_mcp_conn(), %{
               "source_key" => "qonto-main",
               "transaction_external_id" => "transaction-1",
               "document_id" => document.id
             })

    assert result.success
    assert result.attachment_id == "attachment-1"
    assert result.filename == "receipt.pdf"
  end

  defp insert_document! do
    storage_key = "documents/#{System.unique_integer([:positive])}/receipt.pdf"

    %Document{}
    |> Document.changeset(%{
      title: "Receipt",
      original_filename: "receipt.pdf",
      content_type: "application/pdf",
      byte_size: 16,
      checksum_sha256: "checksum-#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: storage_key,
      source: "upload",
      status: "ready"
    })
    |> Repo.insert!()
  end
end
