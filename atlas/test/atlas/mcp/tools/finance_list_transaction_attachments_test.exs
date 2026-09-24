defmodule Atlas.MCP.Tools.FinanceListTransactionAttachmentsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tools.FinanceListTransactionAttachments

  test "passes the configured source map to the provider" do
    source = %{key: "qonto-main", provider: :qonto, name: "Qonto Main"}

    expect(Config, :fetch_source, fn "qonto-main" -> {:ok, source} end)

    expect(Qonto, :list_transaction_attachments, fn ^source, "transaction-1" ->
      {:ok,
       [
         %{
           "id" => "attachment-1",
           "file_name" => "receipt.pdf",
           "file_content_type" => "application/pdf",
           "file_size" => "42",
           "url" => "https://example.com/receipt.pdf",
           "probative_attachment" => %{}
         }
       ]}
    end)

    assert {:ok, %{attachments: [attachment], count: 1}} =
             execute_tool(FinanceListTransactionAttachments, executive_mcp_conn(), %{
               "source_key" => "qonto-main",
               "transaction_external_id" => "transaction-1"
             })

    assert attachment.id == "attachment-1"
    assert attachment.file_size == 42
    assert attachment.probative
  end
end
