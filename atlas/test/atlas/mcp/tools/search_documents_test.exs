defmodule Atlas.MCP.Tools.SearchDocumentsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.MCP.Tools.SearchDocuments
  alias Atlas.Vector

  test "searches document pages for executives" do
    stub(Vector, :configured?, fn -> false end)
    page = insert_page!("Signed board consent appointing a new managing director.")

    assert {:ok, %{results: [result], count: 1}} =
             execute_tool(SearchDocuments, executive_mcp_conn(), %{"query" => "board consent", "page_size" => 10})

    assert result.id == page.id
    assert result.document_id == page.document_id
    assert result.page_number == 1
  end

  test "rejects non-executive users" do
    conn = %{role: :employee} |> insert_user!() |> mcp_conn()

    assert {:error, "Document tools are only available to executives."} =
             execute_tool(SearchDocuments, conn, %{"query" => "board consent"})
  end

  defp insert_page!(content) do
    document = insert_document!()

    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
    |> Repo.insert!()
  end

  defp insert_document! do
    %Document{}
    |> Document.changeset(%{
      title: "Board Consent",
      original_filename: "board-consent.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    })
    |> Repo.insert!()
  end
end
