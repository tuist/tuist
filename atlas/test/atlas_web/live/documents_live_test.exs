defmodule AtlasWeb.DocumentsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage

  test "renders the executive documents library", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/library/documents")

    assert has_element?(view, "#documents")
    assert has_element?(view, "#documents-add-file")
    assert has_element?(view, "#documents-filters-dropdown")
    assert has_element?(view, "#documents-search-form")
    assert has_element?(view, "#documents-table")

    assert has_element?(
             view,
             ~s(#documents-table a[data-part="sort-link"][href*="sort-by=document_date"]),
             "Document date"
           )

    assert has_element?(view, ~s(#documents-table a[data-part="sort-link"][href*="sort-by=inserted_at"]), "Added")
    assert has_element?(view, ~s(a[href="/library/documents"]), "Documents")
  end

  test "renders correspondent and account in separate aligned cells", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-logo@example.com", role: :executive})

    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    correspondent = Documents.upsert_correspondent("Acme Inc.")

    insert_document!(%{
      title: "Acme Security Review",
      account_id: account.id,
      correspondent_id: correspondent.id
    })

    {:ok, view, _html} = live(conn, ~p"/library/documents")

    assert has_element?(
             view,
             ~s(#documents-table [data-part="cell"][data-type="text"] [data-part="label"]),
             "Acme Inc."
           )

    assert has_element?(
             view,
             ~s(#documents-table [data-part="account-cell"] a[href="/commercial/sales/accounts/#{account.id}"]),
             "Acme"
           )

    refute has_element?(view, ~s(#documents-table img[src*="domain=acme.example"]))
  end

  test "search filters the library to page text matches", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-page-search@example.com", role: :executive})

    matching_document = insert_document!(%{title: "Board Consent"})

    insert_page!(
      matching_document,
      String.duplicate("Introductory filing context. ", 12) <>
        "Signed board consent appointing a new managing director."
    )

    insert_document!(%{title: "Unrelated Invoice"})

    {:ok, view, _html} = live(conn, ~p"/library/documents")

    view
    |> form("#documents-search-form", search: %{query: "managing director"})
    |> render_change()

    assert_patched(view, ~p"/library/documents?search=managing+director")
    refute has_element?(view, "#documents-search-summary")
    assert has_element?(view, "#documents-search-filter", "Search")
    assert has_element?(view, "#documents-search-filter", "contains")
    assert has_element?(view, "#documents-search-filter", "managing director")
    assert has_element?(view, "#documents-table", "Board Consent")
    refute has_element?(view, "#documents-table", "Unrelated Invoice")
    assert has_element?(view, ~s(#documents-table [data-part="match-badges"]), "Page text")
    assert has_element?(view, ~s(#documents-table [data-part="match-excerpt"]), "managing director")
  end

  test "search from the URL filters the library to metadata matches", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-metadata-search@example.com", role: :executive})

    insert_document!(%{title: "Acme Security Review"})
    insert_document!(%{title: "Plain Invoice"})

    {:ok, view, _html} = live(conn, ~p"/library/documents?search=Security")

    refute has_element?(view, "#documents-search-summary")
    assert has_element?(view, "#documents-search-filter", "Security")
    assert has_element?(view, "#documents-table", "Acme Security Review")
    refute has_element?(view, "#documents-table", "Plain Invoice")
    assert has_element?(view, ~s(#documents-table [data-part="match-badges"]), "Metadata")
  end

  test "filters the library using document metadata filters", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-filters@example.com", role: :executive})

    account = insert_account!(%{name: "Acme", primary_domain: "acme.example"})
    invoice_type = Documents.upsert_document_type("invoice")
    contract_type = Documents.upsert_document_type("contract")
    correspondent = Documents.upsert_correspondent("Acme Finance")
    tag = Documents.upsert_tag("renewal")

    matching_document =
      insert_document!(%{
        title: "Acme Renewal Invoice",
        account_id: account.id,
        correspondent_id: correspondent.id,
        document_type_id: invoice_type.id
      })
      |> put_tags!([tag])

    insert_document!(%{title: "Acme Contract", document_type_id: contract_type.id})

    filter_params = %{
      "filter_account_id_op" => "==",
      "filter_account_id_val" => account.id,
      "filter_document_type_op" => "==",
      "filter_document_type_val" => "invoice",
      "filter_tag_op" => "==",
      "filter_tag_val" => "renewal"
    }

    {:ok, view, _html} = live(conn, ~p"/library/documents?#{filter_params}")

    assert has_element?(view, ~s(#documents-table tr[id="documents-table-row-#{matching_document.id}"]))
    refute has_element?(view, "#documents-table", "Acme Contract")
    assert has_element?(view, "#account_id")
    assert has_element?(view, "#document_type")
    assert has_element?(view, "#tag")
  end

  test "filters page-text search results using document metadata filters", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-search-filters@example.com", role: :executive})

    invoice_type = Documents.upsert_document_type("invoice")
    contract_type = Documents.upsert_document_type("contract")

    matching_document = insert_document!(%{title: "Board Invoice", document_type_id: invoice_type.id})
    insert_page!(matching_document, "Signed board consent appointing a new managing director.")

    other_document = insert_document!(%{title: "Board Contract", document_type_id: contract_type.id})
    insert_page!(other_document, "Signed board consent appointing a new managing director.")

    filter_params = %{
      "search" => "managing director",
      "filter_document_type_op" => "==",
      "filter_document_type_val" => "invoice"
    }

    {:ok, view, _html} = live(conn, ~p"/library/documents?#{filter_params}")

    assert has_element?(view, ~s(#documents-table tr[id="documents-table-row-#{matching_document.id}"]))
    refute has_element?(view, ~s(#documents-table tr[id="documents-table-row-#{other_document.id}"]))
    assert has_element?(view, "#documents-search-filter", "managing director")
    assert has_element?(view, "#document_type")
  end

  test "excludes documents using metadata filters", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-exclude-filters@example.com", role: :executive})

    renewal_tag = Documents.upsert_tag("renewal")
    finance_tag = Documents.upsert_tag("finance")

    excluded_document =
      insert_document!(%{title: "Renewal Finance Packet"})
      |> put_tags!([renewal_tag, finance_tag])

    matching_document =
      insert_document!(%{title: "Finance Packet"})
      |> put_tags!([finance_tag])

    filter_params = %{
      "filter_tag_op" => "!=",
      "filter_tag_val" => "renewal"
    }

    {:ok, view, _html} = live(conn, ~p"/library/documents?#{filter_params}")

    assert has_element?(view, ~s(#documents-table tr[id="documents-table-row-#{matching_document.id}"]))
    refute has_element?(view, ~s(#documents-table tr[id="documents-table-row-#{excluded_document.id}"]))
    assert has_element?(view, "#tag")
  end

  test "sorts by document date and added date", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "documents-sorting@example.com", role: :executive})

    newer_document =
      insert_document!(%{
        title: "Newer document date",
        document_date: ~D[2026-03-01],
        inserted_at: ~N[2026-01-01 10:00:00]
      })

    older_document =
      insert_document!(%{
        title: "Older document date",
        document_date: ~D[2026-01-01],
        inserted_at: ~N[2026-03-01 10:00:00]
      })

    {:ok, document_date_view, _html} =
      live(conn, ~p"/library/documents?#{%{"sort-by" => "document_date", "sort-order" => "asc"}}")

    assert has_element?(
             document_date_view,
             ~s(#documents-table a[data-part="sort-link"][href*="sort-by=document_date"] [data-state="asc"])
           )

    assert document_row_ids(document_date_view) == [
             "documents-table-row-#{older_document.id}",
             "documents-table-row-#{newer_document.id}"
           ]

    {:ok, added_date_view, _html} =
      live(conn, ~p"/library/documents?#{%{"sort-by" => "inserted_at", "sort-order" => "desc"}}")

    assert has_element?(
             added_date_view,
             ~s(#documents-table a[data-part="sort-link"][href*="sort-by=inserted_at"] [data-state="desc"])
           )

    assert document_row_ids(added_date_view) == [
             "documents-table-row-#{older_document.id}",
             "documents-table-row-#{newer_document.id}"
           ]
  end

  test "redirects employees away from documents", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "employee-documents@example.com", role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/library/documents")
  end

  describe "subtitle/1" do
    test "prefers the Paperless title when present" do
      doc = %{attributes: %{"paperless_title" => "Acme MSA"}, original_filename: "acme-msa-final-v3.pdf"}
      assert AtlasWeb.DocumentsLive.subtitle(doc) == "Acme MSA"
    end

    test "falls back to the filename without a Paperless title" do
      assert AtlasWeb.DocumentsLive.subtitle(%{attributes: %{}, original_filename: "upload.pdf"}) == "upload.pdf"

      assert AtlasWeb.DocumentsLive.subtitle(%{attributes: %{"paperless_title" => ""}, original_filename: "x.pdf"}) ==
               "x.pdf"
    end
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

    {manual_attrs, attrs} =
      defaults
      |> Map.merge(attrs)
      |> Map.split([:account_id, :document_type_id, :correspondent_id, :uploaded_by_id, :inserted_at, :updated_at])

    %Document{}
    |> Document.changeset(attrs)
    |> Ecto.Changeset.change(manual_attrs)
    |> Atlas.Repo.insert!()
  end

  defp put_tags!(%Document{} = document, tags) when is_list(tags) do
    document
    |> Atlas.Repo.preload(:tags)
    |> Document.tags_changeset(tags)
    |> Atlas.Repo.update!()
  end

  defp insert_page!(document, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
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

  defp document_row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s(#documents-table tbody tr[id^="documents-table-row-"]))
    |> Enum.map(fn row -> row |> LazyHTML.attribute("id") |> List.first() end)
  end
end
