defmodule AtlasWeb.FinancingsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.FinancingsFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Documents.Document
  alias Atlas.Finance.Financings
  alias Atlas.Repo

  test "renders the financings index as executive", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "exec-#{System.unique_integer([:positive])}@tuist.dev",
        role: :executive
      })

    financing = insert_financing!()

    {:ok, view, _html} = live(conn, ~p"/hardware/financings")

    assert has_element?(view, "#financings")
    assert has_element?(view, "#financings-row-#{financing.id}")
  end

  test "shows a financing detail page as executive", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "exec-#{System.unique_integer([:positive])}@tuist.dev",
        role: :executive
      })

    financing = insert_financing!()

    {:ok, view, _html} = live(conn, ~p"/hardware/financings/#{financing.id}")

    assert has_element?(view, "#financing-show")
    assert has_element?(view, "#financing-breadcrumb-current", financing.provider)
    assert has_element?(view, "#attach-financing-document-button")
    assert has_element?(view, "#attach-financing-document-modal")
    assert has_element?(view, "#financing-documents-table")
  end

  test "attaches and detaches a typed document", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "exec-#{System.unique_integer([:positive])}@tuist.dev",
        role: :executive
      })

    financing = insert_financing!(%{supplier: "Apple"})
    document = insert_document!("Apple supplier contract")

    {:ok, view, _html} = live(conn, ~p"/hardware/financings/#{financing.id}")

    render_submit(view, "attach_document", %{
      document: %{document_id: document.id, kind: "supplier_contract", notes: "Order 2214808999"}
    })

    [link] = Financings.list_documents(financing)
    assert has_element?(view, "#financing-document-#{link.id}")
    assert has_element?(view, "#financing-document-#{link.id}", "Apple supplier contract")

    view
    |> element("#detach-financing-document-#{link.id}")
    |> render_click()

    refute has_element?(view, "#financing-document-#{link.id}")
    assert Repo.get(Document, document.id)
  end

  test "searches and selects a document by its title", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "exec-#{System.unique_integer([:positive])}@tuist.dev",
        role: :executive
      })

    financing = insert_financing!()
    document = insert_document!("Targo financing guarantee")

    {:ok, view, _html} = live(conn, ~p"/hardware/financings/#{financing.id}")

    render_change(view, "search_financing_documents", %{
      "document_search" => %{"query" => "Targo financing"}
    })

    render_click(view, "select_financing_document", %{"id" => document.id})

    render_submit(view, "attach_document", %{
      "document" => %{
        "document_id" => document.id,
        "kind" => "guarantee",
        "notes" => "Financing guarantee"
      }
    })

    [link] = Financings.list_documents(financing)
    assert link.document_id == document.id
    assert link.kind == "guarantee"
    assert has_element?(view, "#financing-document-#{link.id}", "Targo financing guarantee")
  end

  test "denies non-executive access", %{conn: conn} do
    {conn, _user} =
      log_in_user(conn, %{
        email: "employee-#{System.unique_integer([:positive])}@tuist.dev"
      })

    assert {:error, {:redirect, %{}}} = live(conn, ~p"/hardware/financings")
  end

  defp insert_document!(title) do
    unique = System.unique_integer([:positive])

    %Document{}
    |> Document.changeset(%{
      title: title,
      original_filename: "financing-#{unique}.pdf",
      content_type: "application/pdf",
      byte_size: 100,
      checksum_sha256: "checksum-#{unique}",
      storage_bucket: "test-documents",
      storage_key: "financings/#{unique}.pdf",
      source: "upload",
      status: "ready"
    })
    |> Repo.insert!()
  end
end
