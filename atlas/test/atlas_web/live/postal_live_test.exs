defmodule AtlasWeb.PostalLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Documents.Storage
  alias Atlas.Letters
  alias Atlas.Repo

  test "lists ready-to-sign requests with their prepared document", %{conn: conn} do
    {conn, executive} =
      log_in_user(conn, %{
        email: "postal-executive-#{System.unique_integer([:positive])}@example.com",
        role: :executive
      })

    account = insert_tax_certificate_account!()

    assert {:ok, letter} = Letters.prepare_tax_certificate(account, request_attrs(), executive)

    {:ok, view, _html} = live(conn, ~p"/postal")

    assert has_element?(view, "#postal")
    assert has_element?(view, "#postal-search-form")
    assert has_element?(view, "#postal-filters-dropdown")
    assert has_element?(view, "#postal-letters-table")
    assert has_element?(view, "#postal-upload-letter-button")
    assert has_element?(view, "#postal-upload-letter-button input[type='file']")
    refute has_element?(view, "#postal-delivery-not-configured")

    assert has_element?(
             view,
             "#postal-letter-account-#{letter.id}[href='/sales/accounts/#{account.id}']",
             account.name
           )

    assert has_element?(view, "#postal-letter-document-#{letter.id}")
    refute has_element?(view, "#postal-letter-actions-#{letter.id}")
  end

  test "lists uploaded letters with links to their signed documents", %{conn: conn} do
    {conn, executive} =
      log_in_user(conn, %{
        email: "postal-delivery-#{System.unique_integer([:positive])}@example.com",
        role: :executive
      })

    account = insert_tax_certificate_account!()

    assert {:ok, letter} = Letters.prepare_tax_certificate(account, request_attrs(), executive)
    assert {:ok, %{body: prepared_pdf}} = Storage.get_object(letter.document.storage_key)

    assert {:ok, signed} =
             Letters.attach_letter_document(
               letter,
               %{body: prepared_pdf <> "\n% signed by the executive", filename: "signed-request.pdf"},
               executive
             )

    assert {:ok, ready_to_deliver} = Letters.prepare_delivery_details(signed)

    {:ok, view, _html} = live(conn, ~p"/postal")

    assert has_element?(
             view,
             "#postal-letter-account-#{ready_to_deliver.id}[href='/sales/accounts/#{account.id}']",
             account.name
           )

    assert has_element?(view, "#postal-letter-actions-#{ready_to_deliver.id}")
    assert has_element?(view, "#postal-letter-actions-#{ready_to_deliver.id}-button")
    assert has_element?(view, "#postal-letter-actions-#{ready_to_deliver.id}-button", "Open document")
  end

  test "renders the letter modal", %{conn: conn} do
    {conn, executive} =
      log_in_user(conn, %{
        email: "postal-signing-#{System.unique_integer([:positive])}@example.com",
        role: :executive
      })

    account = insert_tax_certificate_account!()

    assert {:ok, _letter} = Letters.prepare_tax_certificate(account, request_attrs(), executive)

    {:ok, view, _html} = live(conn, ~p"/postal")

    assert has_element?(view, "#postal-letter-action-modal")
  end

  test "restricts postal delivery to leadership", %{conn: conn} do
    {conn, _employee} =
      log_in_user(conn, %{
        email: "postal-employee-#{System.unique_integer([:positive])}@example.com",
        role: :employee
      })

    assert {:error, {:redirect, %{to: "/sales"}}} = live(conn, ~p"/postal")
  end

  defp request_attrs do
    %{
      "recipient_name" => "Finanzamt Berlin",
      "recipient_street" => "Musterstraße 1",
      "recipient_postal_code" => "10115",
      "recipient_city" => "Berlin",
      "foundation_date" => "2020-01-01",
      "legal_form" => "GmbH",
      "submission_to" => "Vergabestelle Berlin",
      "certificate_purpose" => "Teilnahme an einem Vergabeverfahren",
      "signing_location" => "Berlin"
    }
  end

  defp insert_tax_certificate_account! do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "postal-account-#{suffix}",
      name: "Atlas GmbH #{suffix}",
      legal_name: "Atlas GmbH #{suffix}",
      segment: :customer,
      address: %{
        street: "Musterstraße 42",
        zip: "10115",
        city: "Berlin",
        country: "DE"
      },
      billing: %{tax_id: "30/123/45678", vat_id: "DE123456789"},
      signatory: %{name: "Mia Example", title: "Geschäftsführerin"}
    })
    |> Repo.insert!()
  end
end
