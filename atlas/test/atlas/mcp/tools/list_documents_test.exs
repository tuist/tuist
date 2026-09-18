defmodule Atlas.MCP.Tools.ListDocumentsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Documents.Document
  alias Atlas.MCP.Tools.ListDocuments

  test "lists documents for executives" do
    document = insert_document!(%{title: "Board Pack"})

    assert {:ok, %{documents: [result], count: 1}} = execute_tool(ListDocuments, executive_mcp_conn(), %{})
    assert result.id == document.id
    assert result.title == "Board Pack"
  end

  test "filters and serializes documents by account" do
    account = insert_account!(%{account_key: "demo:acme", name: "Acme", primary_domain: "acme.example"})
    document = insert_document!(%{title: "Acme MSA", account_id: account.id})
    _other_document = insert_document!(%{title: "Board Pack"})

    assert {:ok, %{documents: [result], count: 1}} =
             execute_tool(ListDocuments, executive_mcp_conn(), %{"account_key" => "demo:acme"})

    assert result.id == document.id
    assert result.account.name == "Acme"
    assert result.account.url =~ "/commercial/sales/accounts/#{account.id}"
  end

  test "rejects non-executive users" do
    conn = %{role: :employee} |> insert_user!() |> mcp_conn()

    assert {:error, "Document tools are only available to executives."} = execute_tool(ListDocuments, conn, %{})
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

    {foreign_keys, cast_attrs} = Map.split(Map.merge(defaults, attrs), [:account_id])

    %Document{}
    |> Document.changeset(cast_attrs)
    |> Ecto.Changeset.change(foreign_keys)
    |> Repo.insert!()
  end
end
