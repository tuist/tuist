defmodule Atlas.MCP.Tools.FinanceDeleteTransactionAttachmentTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tools.FinanceDeleteTransactionAttachment

  test "passes the configured source map to the provider" do
    source = %{key: "qonto-main", provider: :qonto, name: "Qonto Main"}

    expect(Config, :fetch_source, fn "qonto-main" -> {:ok, source} end)
    expect(Qonto, :delete_attachment, fn ^source, "attachment-1" -> :ok end)

    assert {:ok, result} =
             execute_tool(FinanceDeleteTransactionAttachment, executive_mcp_conn(), %{
               "source_key" => "qonto-main",
               "attachment_id" => "attachment-1"
             })

    assert result.success
    assert result.attachment_id == "attachment-1"
  end
end
