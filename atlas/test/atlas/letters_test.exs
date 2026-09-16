defmodule Atlas.LettersTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.Documents.Storage
  alias Atlas.Letters
  alias Atlas.Letters.Config
  alias Atlas.Letters.Letter
  alias Atlas.Letters.Pingen
  alias Atlas.Letters.Workers.PrepareDelivery
  alias Atlas.Letters.Workers.SendLetter
  alias Atlas.Repo
  alias Atlas.Users.User

  setup :verify_on_exit!

  setup do
    stub(Config, :configured?, fn -> true end)
    :ok
  end

  test "prefills the Tuist GmbH profile and keeps the selected account as request context" do
    account = insert_tax_account!()

    changeset = Letters.change_tax_certificate_request(account)

    assert Ecto.Changeset.get_field(changeset, :recipient_name) == "Finanzamt für Körperschaften III"
    assert Ecto.Changeset.get_field(changeset, :foundation_date) == ~D[2023-11-08]
    assert Ecto.Changeset.get_field(changeset, :legal_form) == "GmbH"
    assert Ecto.Changeset.get_field(changeset, :submission_to) == account.legal_name
  end

  test "requires an executive and complete official-form details" do
    account = insert_tax_account!()
    employee = insert_user!(%{role: :employee})
    executive = insert_user!(%{role: :executive})

    assert {:error, changeset} =
             Letters.prepare_tax_certificate(account, Map.delete(recipient_attrs(), "certificate_purpose"), executive)

    assert "can't be blank" in errors_on(changeset).certificate_purpose

    assert {:error, :unauthorized} =
             Letters.prepare_tax_certificate(account, recipient_attrs(), employee)

    assert Letters.list_account_letters(account) == []
  end

  test "stores a prepared official form and the uploaded signed copy" do
    account = insert_tax_account!()

    executive =
      insert_user!(%{role: :executive, email: "letter-executive-#{System.unique_integer([:positive])}@tuist.dev"})

    assert {:ok, letter} =
             Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
               Letters.prepare_tax_certificate(account, recipient_attrs(), executive)
             end)

    assert letter.status == "awaiting_signature"
    assert letter.sender_name == "Configured Sender GmbH"
    assert letter.submission_to == "Vergabestelle Berlin"
    assert is_nil(letter.confirmed_by_id)
    assert is_nil(letter.confirmed_at)
    assert letter.document.source == "letter"
    assert letter.document.account_id == account.id
    assert letter.body =~ "Bescheinigung in Steuersachen"

    assert {:ok, %{body: pdf}} = Storage.get_object(letter.document.storage_key)
    assert pdf =~ "%PDF-1.5"
    assert letter.document.attributes["official_template"]["key"] == "berlin-tax-certificate-request"

    assert {:ok, signed} =
             Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
               Letters.attach_letter_document(
                 letter,
                 %{body: signed_pdf(pdf), filename: "signed-request.pdf"},
                 executive
               )
             end)

    assert signed.status == "collecting_delivery_details"
    assert signed.signed_document.source == "letter"
    assert signed.signed_uploaded_by_id == executive.id
    assert_enqueued(worker: PrepareDelivery, args: %{"letter_id" => signed.id})

    assert {:ok, ready} = Letters.prepare_delivery_details(signed)
    assert ready.status == "awaiting_delivery_confirmation"
    assert ready.delivery_prepared_at
    assert ready.delivery_details["recipient"]["name"] == "Finanzamt Berlin"
    assert ready.delivery_details["delivery_product"] == "fast"

    activity = Repo.get_by!(Activity, action: "letter.tax_certificate_prepared", target_id: letter.id)
    assert activity.actor_id == executive.id
    assert activity.interface == "dashboard"
    assert activity.metadata["path"] == "/sales/accounts/#{account.id}"

    upload_activity = Repo.get_by!(Activity, action: "letter.document_attached", target_id: letter.id)
    assert upload_activity.metadata["signed_document_id"] == signed.signed_document_id

    delivery_activity = Repo.get_by!(Activity, action: "letter.delivery_details_prepared", target_id: letter.id)
    assert delivery_activity.interface == "worker"
    assert delivery_activity.metadata["delivery_product"] == "fast"
  end

  test "reserves and finalizes a signed form via presigned upload" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter} =
      Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
        Letters.prepare_tax_certificate(account, recipient_attrs(), executive)
      end)

    {:ok, %{body: prepared_pdf}} = Storage.get_object(letter.document.storage_key)

    assert {:ok, reservation} =
             Letters.create_letter_document_upload(letter.id, %{filename: "signed-request.pdf"}, executive)

    assert %{
             letter: %Letter{status: "awaiting_signature"},
             document: pending_document,
             upload_url: upload_url,
             required_headers: %{"Content-Type" => "application/pdf"}
           } = reservation

    assert pending_document.status == "pending_upload"
    assert pending_document.attributes["letter_id"] == letter.id
    assert pending_document.attributes["letter_version"] == "outgoing"
    assert String.starts_with?(pending_document.original_filename, "letter-#{letter.id}-")
    assert is_binary(upload_url) and upload_url != ""

    # The reservation alone does not advance the letter.
    assert Letters.get_letter(letter.id).status == "awaiting_signature"

    {:ok, _object} = Storage.put_object(pending_document.storage_key, signed_pdf(prepared_pdf))

    assert {:ok, signed} =
             Letters.finalize_letter_document_upload(letter.id, pending_document.id, executive)

    assert signed.status == "collecting_delivery_details"
    assert signed.signed_document_id == pending_document.id
    assert signed.signed_uploaded_by_id == executive.id
    assert_enqueued(worker: PrepareDelivery, args: %{"letter_id" => signed.id})

    finalized_document = Atlas.Documents.get_document(pending_document.id, pages: false)
    assert finalized_document.status == "uploaded"
    assert finalized_document.byte_size == byte_size(signed_pdf(prepared_pdf))
  end

  test "refuses to finalize when the uploaded bytes are not a PDF" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter} = Letters.prepare_tax_certificate(account, recipient_attrs(), executive)

    {:ok, reservation} =
      Letters.create_letter_document_upload(letter.id, %{filename: "signed.pdf"}, executive)

    {:ok, _object} = Storage.put_object(reservation.document.storage_key, "not a pdf")

    assert {:error, :letter_document_must_be_a_pdf} =
             Letters.finalize_letter_document_upload(letter.id, reservation.document.id, executive)

    assert Letters.get_letter(letter.id).status == "awaiting_signature"
    assert Atlas.Documents.get_document(reservation.document.id, pages: false).status == "pending_upload"
  end

  test "forwards a custom expires_in to the presigned reservation" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter} = Letters.prepare_tax_certificate(account, recipient_attrs(), executive)

    {:ok, reservation} =
      Letters.create_letter_document_upload(
        letter.id,
        %{filename: "signed.pdf"},
        executive,
        expires_in: 120
      )

    delta = DateTime.diff(reservation.upload_expires_at, DateTime.utc_now(), :second)
    assert delta > 60 and delta <= 120
  end

  test "refuses to finalize a signed upload from another letter" do
    account_a = insert_tax_account!()
    account_b = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter_a} =
      Letters.prepare_tax_certificate(
        account_a,
        Map.put(recipient_attrs(), "certificate_purpose", "Ausschreibung A"),
        executive
      )

    {:ok, letter_b} =
      Letters.prepare_tax_certificate(
        account_b,
        Map.put(recipient_attrs(), "certificate_purpose", "Ausschreibung B"),
        executive
      )

    {:ok, reservation} =
      Letters.create_letter_document_upload(letter_a.id, %{filename: "signed-a.pdf"}, executive)

    {:ok, _object} = Storage.put_object(reservation.document.storage_key, "%PDF-signed\n")

    assert {:error, :letter_document_letter_mismatch} =
             Letters.finalize_letter_document_upload(letter_b.id, reservation.document.id, executive)

    assert Letters.get_letter(letter_b.id).status == "awaiting_signature"
  end

  test "extracts a delivery address for an uploaded postal letter" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    assert {:ok, prepared} =
             Letters.prepare_tax_certificate(account, recipient_attrs(), executive)

    assert {:ok, %{body: prepared_pdf}} = Storage.get_object(prepared.document.storage_key)

    assert {:ok, uploaded} =
             Letters.upload_letter(
               %{
                 body: prepared_pdf <> "\n% uploaded postal letter\n",
                 filename: "#{account.name}-payment-reminder.pdf"
               },
               executive
             )

    assert uploaded.kind == "uploaded_letter"
    assert uploaded.status == "collecting_delivery_details"
    assert is_nil(uploaded.account_id)
    assert_enqueued(worker: PrepareDelivery, args: %{"letter_id" => uploaded.id})

    assert {:ok, ready} = Letters.prepare_delivery_details(uploaded)
    assert ready.status == "awaiting_delivery_confirmation"
    assert ready.account_id == account.id
    assert ready.recipient_name == "Finanzamt Berlin"
    assert ready.recipient_street == "Musterstraße 1"
    assert ready.recipient_postal_code == "10115"
    assert ready.recipient_city == "Berlin"

    upload_activity = Repo.get_by!(Activity, action: "letter.uploaded", target_id: uploaded.id)
    assert upload_activity.metadata["path"] == "/postal"
  end

  test "persists a delivery confirmation after a leadership status check" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter} =
      Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
        Letters.prepare_tax_certificate(account, recipient_attrs(), executive)
      end)

    {:ok, %{body: pdf}} = Storage.get_object(letter.document.storage_key)

    {:ok, signed} =
      Letters.attach_letter_document(letter, %{body: signed_pdf(pdf), filename: "signed-request.pdf"}, executive)

    assert {:ok, ready} = Letters.prepare_delivery_details(signed)

    assert {:ok, queued} =
             Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
               Letters.confirm_delivery(ready, %{"confirmed" => true}, executive)
             end)

    assert queued.status == "queued"
    assert queued.confirmed_at
    assert_enqueued(worker: SendLetter, args: %{"letter_id" => queued.id})

    provider_letter_id = "provider-letter-#{System.unique_integer([:positive])}"

    expect(Pingen, :send_letter, fn %Letter{id: id}, pdf ->
      assert id == queued.id
      assert pdf =~ "%PDF-1.5"

      {:ok,
       %{
         id: provider_letter_id,
         status: "sent",
         tracking_number: "tracking-#{System.unique_integer([:positive])}",
         submitted_at: ~U[2026-08-26 12:00:00Z],
         delivered_at: nil,
         undeliverable_at: nil,
         raw: %{}
       }}
    end)

    assert {:ok, sent} = Letters.deliver(queued.id)
    assert sent.status == "sent"
    assert sent.sent_at == ~U[2026-08-26 12:00:00Z]

    expect(Pingen, :get_letter, fn ^provider_letter_id ->
      {:ok,
       %{
         id: provider_letter_id,
         status: "delivered",
         tracking_number: sent.pingen_tracking_number,
         submitted_at: sent.sent_at,
         delivered_at: ~U[2026-08-28 09:30:00Z],
         undeliverable_at: nil,
         raw: %{}
       }}
    end)

    assert {:ok, delivered} =
             Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
               Letters.check_delivery(queued.id, executive)
             end)

    assert delivered.status == "delivered"
    assert delivered.delivered_at == ~U[2026-08-28 09:30:00Z]
    assert delivered.last_checked_at

    activity = Repo.get_by!(Activity, action: "letter.delivery_checked", target_id: letter.id)
    assert activity.actor_id == executive.id
    assert activity.interface == "dashboard"
  end

  test "records a verified delivery event once" do
    account = insert_tax_account!()
    executive = insert_user!(%{role: :executive})

    {:ok, letter} =
      Audit.with_context(%{actor: executive, interface: "dashboard"}, fn ->
        Letters.prepare_tax_certificate(account, recipient_attrs(), executive)
      end)

    provider_letter_id = "provider-webhook-#{System.unique_integer([:positive])}"

    _updated_letter =
      letter
      |> Ecto.Changeset.change(pingen_letter_id: provider_letter_id, status: "sent")
      |> Repo.update!()

    payload = %{
      "data" => %{
        "id" => "event-#{System.unique_integer([:positive])}",
        "type" => "webhook_delivered",
        "attributes" => %{"created_at" => "2026-08-28T09:30:00Z"},
        "relationships" => %{"letter" => %{"data" => %{"id" => provider_letter_id}}}
      }
    }

    assert {:ok, delivered} = Letters.record_webhook(payload)
    assert delivered.status == "delivered"
    assert delivered.delivered_at
    assert [%{"id" => event_id}] = delivered.pingen_events["items"]

    assert {:ok, duplicate} = Letters.record_webhook(payload)
    assert [%{"id" => ^event_id}] = duplicate.pingen_events["items"]
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

  defp signed_pdf(pdf), do: pdf <> "\n% signed by the authorized signatory\n"

  defp insert_tax_account! do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "letter-account-#{suffix}",
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

  defp insert_user!(attrs) do
    suffix = System.unique_integer([:positive])

    defaults = %{
      email: "letter-user-#{suffix}@tuist.dev",
      name: "Letter User",
      role: :employee
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
