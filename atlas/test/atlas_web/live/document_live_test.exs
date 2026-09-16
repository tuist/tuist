defmodule AtlasWeb.DocumentLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Documents
  alias Atlas.Documents.Document

  test "renders document details with document and account actions", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "doc-detail@example.com", role: :executive})

    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    correspondent = Documents.upsert_correspondent("Acme Inc.")
    document_type = Documents.upsert_document_type("contract")

    document =
      %{title: "MSA", account_id: account.id, document_type_id: document_type.id, correspondent_id: correspondent.id}
      |> insert_document!()

    {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

    assert has_element?(view, "#document")
    # The download link carries a descriptive trailing filename (title slug + ext).
    assert has_element?(view, ~s(a[href="/documents/#{document.id}/download/msa.txt"]), "Open document")
    assert has_element?(view, ~s(a[href="/sales/accounts/#{account.id}"]), "View account")
    assert has_element?(view, "#document-account-link", account.name)
    assert render(view) =~ "Acme Inc."
  end

  test "redirects when the document is missing", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "doc-missing@example.com", role: :executive})

    assert {:error, {:live_redirect, %{to: "/documents"}}} =
             live(conn, ~p"/documents/#{Ecto.UUID.generate()}")
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

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Atlas.Repo.insert!()
  end
end
