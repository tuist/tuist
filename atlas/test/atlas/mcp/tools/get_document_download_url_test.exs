defmodule Atlas.MCP.Tools.GetDocumentDownloadUrlTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Documents
  alias Atlas.MCP.Tools.GetDocumentDownloadUrl

  setup do
    {:ok, document} =
      Documents.create_from_binary(
        "PK #{System.unique_integer([:positive])}",
        %{
          "original_filename" => "contract-package-final.zip",
          "content_type" => "application/zip",
          "title" => "Contract package"
        },
        enqueue?: false
      )

    %{document: document}
  end

  test "returns a signed link to the original file", %{document: document} do
    assert {:ok, result} = execute_tool(GetDocumentDownloadUrl, executive_mcp_conn(), %{"document_id" => document.id})

    assert result.filename == "contract-package.zip"
    assert result.content_type == "application/zip"
    assert result.download_url =~ "/documents/#{document.id}/file/contract-package.zip?token="
    assert {:ok, _expires_at, 0} = DateTime.from_iso8601(result.expires_at)
  end

  test "needs document access and never gives a link to the shared Slack identity", %{document: document} do
    assert {:error, message} =
             GetDocumentDownloadUrl.execute(mcp_conn(insert_user!()), %{"document_id" => document.id})

    assert message =~ "documents:read"

    slack = put_in(executive_mcp_conn().assigns[:audit_interface], "slack")
    assert {:error, message} = GetDocumentDownloadUrl.execute(slack, %{"document_id" => document.id})
    assert message =~ "shared Slack"

    assert {:error, "Document not found."} =
             GetDocumentDownloadUrl.execute(executive_mcp_conn(), %{"document_id" => "not-a-uuid"})
  end
end
