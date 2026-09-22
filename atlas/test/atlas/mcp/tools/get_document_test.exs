defmodule Atlas.MCP.Tools.GetDocumentTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.MCP.Tools.GetDocument

  test "returns normalized metadata and a shareable url" do
    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    correspondent = Documents.upsert_correspondent("Acme Inc.")
    document_type = Documents.upsert_document_type("contract")
    tags = Documents.upsert_tags(["legal", "renewal"])

    document =
      %{title: "MSA", account_id: account.id, document_type_id: document_type.id, correspondent_id: correspondent.id}
      |> insert_document!()

    {:ok, _document} =
      document
      |> Atlas.Repo.preload(:tags)
      |> Document.tags_changeset(tags)
      |> Atlas.Repo.update()

    assert {:ok, result} = execute_tool(GetDocument, executive_mcp_conn(), %{"document_id" => document.id})

    assert result.document_type == "contract"
    assert result.correspondent == "Acme Inc."
    assert result.account.name == "Acme"
    assert Enum.sort(result.tags) == ["legal", "renewal"]
    assert result.url =~ "/documents/#{document.id}/download/msa.txt"
  end

  test "returns a bounded first page chunk by default" do
    document = insert_document!(%{title: "Long Agreement"})
    for page_number <- 1..12, do: insert_page!(document, page_number, "Page #{page_number} content")

    assert {:ok, result} = execute_tool(GetDocument, executive_mcp_conn(), %{"document_id" => document.id})

    assert result.page_count == 12
    assert result.start_page == 1
    assert result.page_size == 10
    assert result.pages_returned == 10
    assert result.next_start_page == 11
    assert Enum.map(result.pages, & &1.page_number) == Enum.to_list(1..10)
  end

  test "returns requested page chunks" do
    document = insert_document!(%{title: "Long Agreement"})
    for page_number <- 1..12, do: insert_page!(document, page_number, "Page #{page_number} content")

    assert {:ok, result} =
             execute_tool(GetDocument, executive_mcp_conn(), %{
               "document_id" => document.id,
               "start_page" => 11,
               "page_size" => 25
             })

    assert result.page_count == 12
    assert result.start_page == 11
    assert result.page_size == 25
    assert result.pages_returned == 2
    assert result.next_start_page == nil
    assert Enum.map(result.pages, & &1.content) == ["Page 11 content", "Page 12 content"]
  end

  defp insert_document!(attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    {foreign_keys, cast_attrs} =
      Map.split(Map.merge(defaults, attrs), [:account_id, :document_type_id, :correspondent_id, :uploaded_by_id])

    %Document{}
    |> Document.changeset(cast_attrs)
    |> Ecto.Changeset.change(foreign_keys)
    |> Atlas.Repo.insert!()
  end

  defp insert_page!(%Document{} = document, page_number, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: page_number, content: content})
    |> Atlas.Repo.insert!()
  end
end
