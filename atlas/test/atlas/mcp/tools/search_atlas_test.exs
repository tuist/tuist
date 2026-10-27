defmodule Atlas.MCP.Tools.SearchAtlasTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.MCP.Tools.SearchAtlas
  alias Atlas.Search
  alias Atlas.Vector

  setup :verify_on_exit!

  test "searches indexed Atlas records" do
    stub(Vector, :configured?, fn -> false end)

    account = insert_account!(%{name: "Acme Labs"})
    event = insert_event!(account, %{title: "Security review", body: "Customer asked for SOC2 evidence."})
    Search.index_account_event(event)

    assert {:ok, %{results: [result], count: 1}} =
             execute_tool(SearchAtlas, conn_for(nil), %{
               "query" => "SOC2 evidence",
               "source_types" => ["account_event"],
               "page_size" => 5
             })

    assert result.source_type == "account_event"
    assert result.source_id == event.id
    assert result.account_id == account.id
  end

  test "searches document pages for authorized document sessions" do
    stub(Vector, :configured?, fn -> false end)
    page = insert_document_page!("Signed board consent appointing a managing director.")

    assert {:ok, %{results: [result], count: 1, domains: ["documents"]}} =
             execute_tool(
               SearchAtlas,
               executive_mcp_conn(),
               %{
                 "query" => "board consent",
                 "domains" => ["documents"],
                 "page_size" => 5
               }
             )

    assert result.source_type == "document_page"
    assert result.source_id == page.id
    assert result.document_id == page.document_id
    assert result.page_number == 1
  end

  test "rejects explicit document search when the session lacks the document group" do
    conn =
      executive_mcp_conn()
      |> put_mcp_tool_groups(["finance"])

    assert {:error, "Document search is not available for this Model Context Protocol session."} =
             execute_tool(SearchAtlas, conn, %{"query" => "board consent", "domains" => ["documents"]})
  end

  test "requires a query" do
    assert {:error, "query is required."} = execute_tool(SearchAtlas, conn_for(nil), %{})
  end

  defp insert_document_page!(content) do
    document =
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

    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
    |> Repo.insert!()
  end

  defp put_mcp_tool_groups(conn, groups) do
    %{conn | assigns: Map.put(conn.assigns, :mcp_claims, %{"mcp_tool_groups" => groups})}
  end
end
