defmodule Atlas.MCP.Tools.LetterToolsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Documents.Storage
  alias Atlas.Letters
  alias Atlas.Letters.Config
  alias Atlas.MCP.Tools.CheckLetterDelivery
  alias Atlas.MCP.Tools.ConfirmTaxCertificateDelivery
  alias Atlas.MCP.Tools.CreateLetterDocumentUpload
  alias Atlas.MCP.Tools.FinalizeLetterDocumentUpload
  alias Atlas.MCP.Tools.ListAccountLetters
  alias Atlas.MCP.Tools.RequestTaxCertificateLetter
  alias Atlas.MCP.Tools.UploadPostalLetter
  alias Atlas.Repo

  setup :verify_on_exit!

  setup do
    stub(Config, :configured?, fn -> true end)
    :ok
  end

  test "prepares and lists a tax certificate form for executives" do
    account = insert_tax_account!()
    conn = executive_mcp_conn()

    assert {:ok, %{letter: letter}} =
             execute_tool(
               RequestTaxCertificateLetter,
               conn,
               %{"account_id" => account.id, "certificate_purpose" => "Supplier compliance"}
             )

    assert letter.status == "awaiting_signature"
    refute letter.confirmed_at
    assert letter.document_url =~ "/documents/"

    assert {:ok, %{letters: [listed]}} =
             execute_tool(ListAccountLetters, conn, %{"account_id" => account.id})

    assert listed.id == letter.id
    assert listed.recipient.name == "Finanzamt für Körperschaften III"
  end

  test "uploads a signed form via presigned URL and requires delivery approval" do
    account = insert_tax_account!()
    conn = executive_mcp_conn()

    assert {:ok, %{letter: prepared}} =
             execute_tool(
               RequestTaxCertificateLetter,
               conn,
               Map.put(recipient_attrs(), "account_id", account.id)
             )

    letter = Letters.get_letter(prepared.id)
    assert {:ok, %{body: prepared_pdf}} = Storage.get_object(letter.document.storage_key)

    assert {:ok, reservation} =
             execute_tool(CreateLetterDocumentUpload, conn, %{
               "letter_id" => letter.id,
               "filename" => "signed-tax-certificate.pdf"
             })

    assert reservation.letter.status == "awaiting_signature"
    assert reservation.upload_method == "PUT"
    assert is_binary(reservation.upload_url) and reservation.upload_url != ""
    assert reservation.required_headers == %{"Content-Type" => "application/pdf"}
    assert is_binary(reservation.upload_expires_at)

    pending_document = Atlas.Documents.get_document(reservation.document_id, pages: false)
    assert pending_document.status == "pending_upload"
    {:ok, _object} = Storage.put_object(pending_document.storage_key, prepared_pdf <> "\n% signed by an executive\n")

    assert {:ok, %{letter: signed}} =
             execute_tool(FinalizeLetterDocumentUpload, conn, %{
               "letter_id" => letter.id,
               "document_id" => reservation.document_id
             })

    assert signed.status == "collecting_delivery_details"
    assert signed.signed_document_url =~ "/documents/"

    assert {:ok, ready} = Letters.prepare_delivery_details(signed.id)
    assert ready.status == "awaiting_delivery_confirmation"

    assert {:ok, %{letter: queued}} =
             execute_tool(ConfirmTaxCertificateDelivery, conn, %{
               "letter_id" => ready.id,
               "confirmed" => true
             })

    assert queued.status == "queued"
    assert queued.confirmed_at
  end

  test "rejects finalizing a signed form for a mismatched letter" do
    account_a = insert_tax_account!()
    account_b = insert_tax_account!()
    conn = executive_mcp_conn()

    assert {:ok, %{letter: letter_a}} =
             execute_tool(
               RequestTaxCertificateLetter,
               conn,
               recipient_attrs()
               |> Map.put("account_id", account_a.id)
               |> Map.put("certificate_purpose", "Ausschreibung A")
             )

    assert {:ok, %{letter: letter_b}} =
             execute_tool(
               RequestTaxCertificateLetter,
               conn,
               recipient_attrs()
               |> Map.put("account_id", account_b.id)
               |> Map.put("certificate_purpose", "Ausschreibung B")
             )

    assert {:ok, reservation_a} =
             execute_tool(CreateLetterDocumentUpload, conn, %{
               "letter_id" => letter_a.id,
               "filename" => "signed-a.pdf"
             })

    pending_a = Atlas.Documents.get_document(reservation_a.document_id, pages: false)
    {:ok, _object} = Storage.put_object(pending_a.storage_key, "%PDF-signed\n")

    assert {:error, message} =
             execute_tool(FinalizeLetterDocumentUpload, conn, %{
               "letter_id" => letter_b.id,
               "document_id" => reservation_a.document_id
             })

    assert message =~ "does not belong to this letter"
  end

  test "uploads an outbound letter and queues delivery address preparation" do
    account = insert_tax_account!()
    conn = executive_mcp_conn()

    assert {:ok, %{letter: prepared}} =
             execute_tool(
               RequestTaxCertificateLetter,
               conn,
               Map.put(recipient_attrs(), "account_id", account.id)
             )

    prepared_letter = Letters.get_letter(prepared.id)
    assert {:ok, %{body: prepared_pdf}} = Storage.get_object(prepared_letter.document.storage_key)

    assert {:ok, %{letter: uploaded}} =
             execute_tool(UploadPostalLetter, conn, %{
               "filename" => "payment-reminder.pdf",
               "pdf_base64" => Base.encode64(prepared_pdf <> "\n% uploaded postal letter\n")
             })

    assert uploaded.kind == "uploaded_letter"
    assert uploaded.status == "collecting_delivery_details"
    assert uploaded.document_url =~ "/documents/"
  end

  test "rejects incomplete forms and non-executive letter access" do
    account = insert_tax_account!()
    executive = executive_mcp_conn()
    employee = mcp_conn(insert_user!(%{role: :employee}))

    assert {:error, message} =
             execute_tool(
               RequestTaxCertificateLetter,
               executive,
               recipient_attrs() |> Map.delete("certificate_purpose") |> Map.put("account_id", account.id)
             )

    assert message =~ "purpose"

    assert {:error, message} =
             execute_tool(
               RequestTaxCertificateLetter,
               employee,
               Map.put(recipient_attrs(), "account_id", account.id)
             )

    assert message =~ "Letter tools"

    assert {:error, list_message} =
             execute_tool(ListAccountLetters, employee, %{"account_id" => account.id})

    assert list_message =~ "Letter tools"

    assert {:error, check_message} =
             execute_tool(CheckLetterDelivery, employee, %{"letter_id" => "letter-id"})

    assert check_message =~ "Letter tools"
  end

  defp recipient_attrs do
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

  defp insert_tax_account! do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "mcp-letter-account-#{suffix}",
      name: "Atlas GmbH #{suffix}",
      legal_name: "Atlas GmbH #{suffix}",
      segment: :customer,
      address: %{street: "Musterstraße 42", zip: "10115", city: "Berlin", country: "DE"},
      billing: %{tax_id: "30/123/45678"},
      signatory: %{name: "Mia Example", title: "Geschäftsführerin"}
    })
    |> Repo.insert!()
  end
end
