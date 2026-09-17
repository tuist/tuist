defmodule Atlas.Letters do
  @moduledoc """
  Leadership-only outbound letter workflow.
  """

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.Documents
  alias Atlas.Documents.Storage
  alias Atlas.Letters.Agents.DeliveryDetailsAgent
  alias Atlas.Letters.Config
  alias Atlas.Letters.Letter
  alias Atlas.Letters.Pingen
  alias Atlas.Letters.TaxCertificateRequest
  alias Atlas.Letters.TaxCertificateRequestPDF
  alias Atlas.Letters.Webhook
  alias Atlas.Letters.Workers.PrepareDelivery
  alias Atlas.Letters.Workers.SendLetter
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  def configured?, do: Config.configured?()

  def verify_webhook_signature(raw_body, signature) do
    case Config.webhook_signing_key() do
      signing_key when is_binary(signing_key) and signing_key != "" ->
        Webhook.verify_signature(raw_body, signature, signing_key)

      _missing_key ->
        {:error, :postal_webhook_not_configured}
    end
  end

  def get_letter(id) when is_binary(id), do: Repo.get(Letter, id) |> preload_letter()

  def get_account_letter(%Account{id: account_id}, id) when is_binary(id) do
    Letter
    |> where([letter], letter.id == ^id and letter.account_id == ^account_id)
    |> Repo.one()
    |> preload_letter()
  end

  def list_account_letters(_account, opts \\ [])

  def list_account_letters(%Account{id: account_id}, opts) do
    limit = opts |> Keyword.get(:limit, 25) |> min(100)

    Letter
    |> where([letter], letter.account_id == ^account_id)
    |> order_by([letter], desc: letter.inserted_at, desc: letter.id)
    |> limit(^limit)
    |> preload([:document, :signed_document, :created_by, :confirmed_by, :signed_uploaded_by])
    |> Repo.all()
  end

  def list_account_letters(account_id, opts) when is_binary(account_id),
    do: list_account_letters(%Account{id: account_id}, opts)

  def list_letters(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, 25) |> min(100)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    query =
      Letter
      |> maybe_filter_account(Keyword.get(opts, :account_id))
      |> maybe_filter_status(Keyword.get(opts, :status))
      |> maybe_search(Keyword.get(opts, :query))
      |> order_letters(Keyword.get(opts, :sort_by), Keyword.get(opts, :sort_order))
      |> preload([:account, :document, :signed_document, :created_by, :confirmed_by, :signed_uploaded_by])

    {letters, meta} = Flop.run(query, %Flop{limit: page_size, offset: offset}, for: Letter)
    {letters, %{total_count: meta.total_count || length(letters), has_next_page?: meta.has_next_page?}}
  end

  def list_letter_accounts do
    Letter
    |> join(:inner, [letter], account in assoc(letter, :account))
    |> order_by([_letter, account], asc: account.name)
    |> distinct([_letter, account], account.id)
    |> select([_letter, account], account)
    |> Repo.all()
  end

  def change_tax_certificate_request(%Account{} = account, attrs \\ %{}) do
    account
    |> new_tax_certificate_request(nil)
    |> Letter.tax_certificate_request_changeset(tax_certificate_attrs(account, attrs))
  end

  def prepare_tax_certificate(%Account{} = account, attrs, %User{} = actor) when is_map(attrs) do
    with :ok <- authorize(actor),
         [] <- TaxCertificateRequest.missing_sender_fields(),
         {:ok, letter} <- build_tax_certificate_request(account, attrs, actor),
         {:ok, document} <- store_prepared_letter_document(letter, actor),
         {:ok, letter} <- insert_letter(letter, document),
         :ok <- audit("letter.tax_certificate_prepared", letter, actor, %{"document_id" => document.id}) do
      {:ok, preload_letter(letter)}
    else
      {:error, _reason} = error -> error
      missing when is_list(missing) -> {:error, {:sender_details_missing, missing}}
    end
  end

  def prepare_tax_certificate(_account, _attrs, _actor), do: {:error, :unauthorized}

  def request_tax_certificate(account, attrs, actor), do: prepare_tax_certificate(account, attrs, actor)

  def attach_letter_document(%Letter{status: "awaiting_signature"} = letter, upload, %User{} = actor)
      when is_map(upload) do
    with :ok <- authorize(actor),
         :ok <- verify_pdf_upload(upload),
         {:ok, document} <- store_letter_document(letter, upload, actor) do
      set_letter_document(letter, document, actor)
    end
  end

  def attach_letter_document(letter_id, upload, %User{} = actor) when is_binary(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      letter -> attach_letter_document(letter, upload, actor)
    end
  end

  def attach_letter_document(%Letter{}, _upload, _actor), do: {:error, :letter_not_waiting_for_document}
  def attach_letter_document(_letter, _upload, _actor), do: {:error, :unauthorized}

  @doc """
  Reserves a pending outgoing document for a letter that is waiting for one
  and returns a short-lived presigned URL. The client `PUT`s the PDF bytes to
  that URL, then calls `finalize_letter_document_upload/3` to attach the
  document and advance the letter. Rows whose `upload_expires_at` passes are
  swept by `Atlas.Documents.Workers.ExpirePendingUploads`; the letter stays
  at `awaiting_signature` until finalize succeeds.

  Options:
    * `:expires_in` - presigned URL lifetime in seconds. Forwarded to
      `Documents.create_pending_upload/2`, which enforces its own bounds and
      default.
  """
  def create_letter_document_upload(letter_id, attrs, actor, opts \\ [])

  def create_letter_document_upload(letter_id, %{filename: filename}, %User{} = actor, opts)
      when is_binary(letter_id) and is_binary(filename) and filename != "" do
    with :ok <- authorize(actor),
         {:ok, letter} <- fetch_letter_awaiting_document(letter_id) do
      document_attrs = %{
        "original_filename" => outgoing_letter_document_filename(letter, filename),
        "content_type" => "application/pdf",
        "title" => letter_document_title(letter),
        "source" => "letter",
        "document_date" => Date.utc_today(),
        "account_id" => letter.account_id,
        "uploaded_by_id" => actor.id,
        "attributes" => %{
          "letter_id" => letter.id,
          "letter_kind" => letter.kind,
          "letter_version" => "outgoing"
        }
      }

      document_opts = [audit_actor: actor] |> maybe_put_expires_in(opts)

      case Documents.create_pending_upload(document_attrs, document_opts) do
        {:ok, reservation} -> {:ok, Map.put(reservation, :letter, letter)}
        {:error, _reason} = error -> error
      end
    end
  end

  def create_letter_document_upload(_letter_id, _attrs, _actor, _opts), do: {:error, :letter_document_filename_missing}

  @doc """
  Promotes a pending outgoing letter document, attaches it to the letter,
  moves the letter to `collecting_delivery_details`, and enqueues delivery
  preparation. Verifies the document belongs to this letter's reservation so
  a caller cannot attach an arbitrary pending upload, and verifies the
  uploaded bytes are a Portable Document Format file before advancing state
  so a caller that sent the required `Content-Type` header with non-PDF
  bytes does not push corrupt content downstream to the postal provider.
  """
  def finalize_letter_document_upload(letter_id, document_id, %User{} = actor)
      when is_binary(letter_id) and is_binary(document_id) do
    with :ok <- authorize(actor),
         {:ok, letter} <- fetch_letter_awaiting_document(letter_id),
         {:ok, pending} <- fetch_pending_letter_document(letter, document_id),
         {:ok, finalized} <-
           Documents.finalize_pending_upload(pending.id,
             enqueue?: false,
             audit_actor: actor,
             verify_body: &verify_letter_document_bytes/1
           ) do
      set_letter_document(letter, finalized, actor)
    end
  end

  def finalize_letter_document_upload(_letter_id, _document_id, _actor), do: {:error, :unauthorized}

  defp maybe_put_expires_in(document_opts, opts) do
    case Keyword.get(opts, :expires_in) do
      value when is_integer(value) and value > 0 -> Keyword.put(document_opts, :expires_in, value)
      _ -> document_opts
    end
  end

  defp verify_letter_document_bytes(<<"%PDF-", _rest::binary>>), do: :ok
  defp verify_letter_document_bytes(_body), do: {:error, :letter_document_must_be_a_pdf}

  defp fetch_letter_awaiting_document(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      %Letter{status: "awaiting_signature"} = letter -> {:ok, letter}
      %Letter{} -> {:error, :letter_not_waiting_for_document}
    end
  end

  defp fetch_pending_letter_document(%Letter{id: letter_id}, document_id) do
    case Documents.get_document(document_id, pages: false) do
      nil ->
        {:error, :letter_document_not_found}

      %{status: "pending_upload", attributes: %{"letter_id" => ^letter_id, "letter_version" => "outgoing"}} = document ->
        {:ok, document}

      %{status: "pending_upload"} ->
        {:error, :letter_document_letter_mismatch}

      %{status: status} ->
        {:error, {:letter_document_unexpected_status, status}}
    end
  end

  defp set_letter_document(%Letter{} = letter, document, %User{} = actor) do
    with {:ok, updated} <-
           update_letter(letter, %{
             signed_document_id: document.id,
             signed_uploaded_by_id: actor.id,
             signed_uploaded_at: DateTime.utc_now() |> DateTime.truncate(:second),
             status: "collecting_delivery_details"
           }),
         {:ok, _job} <- enqueue_delivery_preparation(updated),
         :ok <- audit("letter.document_attached", updated, actor, %{"signed_document_id" => document.id}) do
      {:ok, preload_letter(updated)}
    end
  end

  def upload_letter(upload, %User{} = actor) when is_map(upload) do
    with :ok <- authorize(actor),
         [] <- TaxCertificateRequest.missing_sender_fields(),
         :ok <- verify_pdf_upload(upload),
         letter = new_uploaded_letter(nil, actor, upload.filename),
         {:ok, document} <- store_uploaded_letter_document(letter, upload, actor),
         {:ok, letter} <- insert_letter(letter, document),
         {:ok, _job} <- enqueue_delivery_preparation(letter),
         :ok <- audit("letter.uploaded", letter, actor, %{"document_id" => document.id, "path" => "/outbound/postal"}) do
      {:ok, preload_letter(letter)}
    else
      {:error, _reason} = error -> error
      missing when is_list(missing) -> {:error, {:sender_details_missing, missing}}
    end
  end

  def upload_letter(%Account{} = account, upload, %User{} = actor) when is_map(upload) do
    with :ok <- authorize(actor),
         [] <- TaxCertificateRequest.missing_sender_fields(),
         :ok <- verify_pdf_upload(upload),
         letter = new_uploaded_letter(account, actor, upload.filename),
         {:ok, document} <- store_uploaded_letter_document(letter, upload, actor),
         {:ok, letter} <- insert_letter(letter, document),
         {:ok, _job} <- enqueue_delivery_preparation(letter),
         :ok <- audit("letter.uploaded", letter, actor, %{"document_id" => document.id, "path" => "/outbound/postal"}) do
      {:ok, preload_letter(letter)}
    else
      {:error, _reason} = error -> error
      missing when is_list(missing) -> {:error, {:sender_details_missing, missing}}
    end
  end

  def upload_letter(account_id, upload, %User{} = actor) when is_binary(account_id) and is_map(upload) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :account_not_found}
      account -> upload_letter(account, upload, actor)
    end
  end

  def upload_letter(_account, _upload, _actor), do: {:error, :unauthorized}

  def prepare_delivery_details(letter_id) when is_binary(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      letter -> prepare_delivery_details(letter)
    end
  end

  def prepare_delivery_details(%Letter{status: "collecting_delivery_details"} = letter) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, letter} <- prepare_uploaded_letter_document(letter),
         {:ok, %{delivery_details: delivery_details, recipient: recipient}} <- DeliveryDetailsAgent.prepare(letter),
         {:ok, updated} <-
           update_letter(
             letter,
             Map.merge(recipient, %{
               delivery_details: delivery_details,
               delivery_prepared_at: now,
               last_error: nil,
               status: "awaiting_delivery_confirmation"
             })
           ),
         :ok <-
           audit(
             "letter.delivery_details_prepared",
             updated,
             letter.signed_uploaded_by || letter.created_by,
             %{"delivery_product" => delivery_details["delivery_product"]},
             interface: "worker"
           ) do
      {:ok, preload_letter(updated)}
    end
  end

  def prepare_delivery_details(%Letter{}), do: {:error, :letter_not_waiting_for_delivery_details}

  def confirm_delivery(%Letter{status: "awaiting_delivery_confirmation"} = letter, attrs, %User{} = actor)
      when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with :ok <- require_confirmation(attrs),
         :ok <- authorize(actor),
         :ok <- require_configured(),
         {:ok, queued} <-
           update_letter(letter, %{
             status: "queued",
             confirmed_by_id: actor.id,
             confirmed_at: now,
             last_error: nil
           }),
         {:ok, _job} <- enqueue_send(queued),
         :ok <- audit("letter.delivery_confirmed", queued, actor, %{}) do
      {:ok, preload_letter(queued)}
    else
      :disabled -> {:error, :postal_delivery_not_configured}
      {:error, _reason} = error -> error
    end
  end

  def confirm_delivery(letter_id, attrs, %User{} = actor) when is_binary(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      letter -> confirm_delivery(letter, attrs, actor)
    end
  end

  def confirm_delivery(%Letter{}, _attrs, _actor), do: {:error, :letter_not_ready_to_send}
  def confirm_delivery(_letter, _attrs, _actor), do: {:error, :unauthorized}

  def check_delivery(%Letter{} = letter, %User{} = actor) do
    with :ok <- authorize(actor),
         pingen_letter_id when is_binary(pingen_letter_id) <- letter.pingen_letter_id,
         {:ok, delivery} <- Pingen.get_letter(pingen_letter_id),
         {:ok, updated} <- apply_provider_delivery(letter, delivery, "poll") do
      audit("letter.delivery_checked", updated, actor, %{"pingen_status" => updated.pingen_status})
      {:ok, preload_letter(updated)}
    else
      :disabled -> {:error, :postal_delivery_not_configured}
      nil -> {:error, :letter_not_submitted}
      {:error, _reason} = error -> error
    end
  end

  def check_delivery(letter_id, %User{} = actor) when is_binary(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      letter -> check_delivery(letter, actor)
    end
  end

  def deliver(letter_id) when is_binary(letter_id) do
    case get_letter(letter_id) do
      nil -> {:error, :not_found}
      %Letter{status: status} when status in ["sent", "delivered", "undeliverable"] -> :ok
      %Letter{status: "queued"} = letter -> do_deliver(letter)
      _letter -> {:error, :letter_not_ready_to_send}
    end
  end

  def record_webhook(payload) when is_map(payload) do
    with {:ok, pingen_letter_id} <- webhook_letter_id(payload),
         %Letter{} = letter <- Repo.get_by(Letter, pingen_letter_id: pingen_letter_id),
         {:ok, updated} <- apply_webhook(letter, payload) do
      audit(
        "letter.webhook_received",
        updated,
        updated.created_by,
        %{
          "webhook_type" => get_in(payload, ["data", "type"]),
          "webhook_id" => get_in(payload, ["data", "id"])
        },
        interface: "api"
      )

      {:ok, updated}
    else
      nil -> {:error, :letter_not_found}
      {:error, _reason} = error -> error
    end
  end

  def record_webhook(_payload), do: {:error, :invalid_payload}

  defp build_tax_certificate_request(account, attrs, actor) do
    letter = new_tax_certificate_request(account, actor)
    changeset = Letter.tax_certificate_request_changeset(letter, tax_certificate_attrs(account, attrs))

    if changeset.valid? do
      letter = Ecto.Changeset.apply_changes(changeset)
      body = TaxCertificateRequest.body(letter)

      {:ok, %{letter | body: body, template_data: template_data(letter)}}
    else
      {:error, changeset}
    end
  end

  defp require_confirmation(%{"confirmed" => confirmed}) when confirmed in [true, "true"], do: :ok
  defp require_confirmation(%{confirmed: confirmed}) when confirmed in [true, "true"], do: :ok
  defp require_confirmation(_attrs), do: {:error, :confirmation_required}

  defp maybe_filter_status(query, status) do
    if status in Letter.statuses() do
      where(query, [letter], letter.status == ^status)
    else
      query
    end
  end

  defp maybe_search(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        match = "%#{value}%"

        where(
          query,
          [letter],
          ilike(letter.subject, ^match) or ilike(letter.recipient_name, ^match) or
            ilike(letter.recipient_city, ^match) or ilike(letter.sender_name, ^match)
        )
    end
  end

  defp maybe_search(query, _value), do: query

  defp order_letters(query, sort_by, sort_order) do
    {field, direction} =
      case {sort_by, sort_order} do
        {"sent_at", "asc"} -> {:sent_at, :asc}
        {"sent_at", _order} -> {:sent_at, :desc}
        {"delivered_at", "asc"} -> {:delivered_at, :asc}
        {"delivered_at", _order} -> {:delivered_at, :desc}
        {"inserted_at", "asc"} -> {:inserted_at, :asc}
        _sort -> {:inserted_at, :desc}
      end

    order_by(query, [letter], [{^direction, field(letter, ^field)}, {^direction, letter.id}])
  end

  defp new_tax_certificate_request(account, actor) do
    snapshot = TaxCertificateRequest.sender_snapshot()

    %Letter{
      id: Atlas.UUIDv7.generate(),
      account_id: account.id,
      created_by_id: actor && actor.id,
      kind: "tax_certificate_request",
      status: "awaiting_signature",
      sender_name: snapshot.sender_name,
      sender_street: snapshot.sender_street,
      sender_postal_code: snapshot.sender_postal_code,
      sender_city: snapshot.sender_city,
      sender_country: snapshot.sender_country,
      signatory_name: snapshot.signatory_name,
      signatory_title: snapshot.signatory_title,
      tax_id: snapshot.tax_id,
      vat_id: snapshot.vat_id,
      subject: TaxCertificateRequest.subject(),
      pingen_events: %{"items" => []},
      template_data: %{}
    }
  end

  defp tax_certificate_attrs(account, attrs) do
    Map.merge(TaxCertificateRequest.form_defaults(account), attrs)
  end

  defp new_uploaded_letter(account, actor, filename) do
    snapshot = TaxCertificateRequest.sender_snapshot()
    subject = uploaded_letter_subject(filename)

    %Letter{
      id: Atlas.UUIDv7.generate(),
      account_id: account && account.id,
      created_by_id: actor.id,
      kind: "uploaded_letter",
      status: "collecting_delivery_details",
      sender_name: Map.get(snapshot, :sender_name),
      sender_street: Map.get(snapshot, :sender_street),
      sender_postal_code: Map.get(snapshot, :sender_postal_code),
      sender_city: Map.get(snapshot, :sender_city),
      sender_country: Map.get(snapshot, :sender_country),
      signatory_name: Map.get(snapshot, :signatory_name),
      signatory_title: Map.get(snapshot, :signatory_title),
      tax_id: Map.get(snapshot, :tax_id),
      vat_id: Map.get(snapshot, :vat_id),
      subject: subject,
      body: "Uploaded letter: #{subject}",
      pingen_events: %{"items" => []},
      template_data: %{}
    }
  end

  defp store_prepared_letter_document(letter, actor) do
    pdf = TaxCertificateRequestPDF.render(letter)

    Documents.create_from_binary(
      pdf,
      %{
        "title" => "Prepared tax certificate request - #{letter.sender_name}",
        "original_filename" => "prepared-tax-certificate-request-#{letter.id}.pdf",
        "content_type" => "application/pdf",
        "source" => "letter",
        "document_date" => Date.utc_today(),
        "account_id" => letter.account_id,
        "uploaded_by_id" => actor.id,
        "attributes" =>
          Map.put(
            %{"letter_id" => letter.id, "letter_kind" => letter.kind, "letter_version" => "prepared"},
            "official_template",
            TaxCertificateRequestPDF.template_metadata()
          )
      },
      enqueue?: false,
      audit_actor: actor
    )
  end

  defp store_letter_document(letter, upload, actor) do
    Documents.create_from_binary(
      upload.body,
      %{
        "title" => letter_document_title(letter),
        "original_filename" => outgoing_letter_document_filename(letter, upload.filename),
        "content_type" => "application/pdf",
        "source" => "letter",
        "document_date" => Date.utc_today(),
        "account_id" => letter.account_id,
        "uploaded_by_id" => actor.id,
        "attributes" => %{
          "letter_id" => letter.id,
          "letter_kind" => letter.kind,
          "letter_version" => "outgoing"
        }
      },
      enqueue?: false,
      audit_actor: actor
    )
  end

  defp store_uploaded_letter_document(letter, upload, actor) do
    Documents.create_from_binary(
      upload.body,
      %{
        "title" => letter.subject,
        "original_filename" => Path.basename(upload.filename),
        "content_type" => "application/pdf",
        "source" => "letter",
        "document_date" => Date.utc_today(),
        "account_id" => letter.account_id,
        "uploaded_by_id" => actor.id,
        "attributes" => %{
          "letter_id" => letter.id,
          "letter_kind" => letter.kind,
          "letter_version" => "uploaded"
        }
      },
      enqueue?: false,
      audit_actor: actor
    )
  end

  defp template_data(letter) do
    %{
      "foundation_date" => if(letter.foundation_date, do: Calendar.strftime(letter.foundation_date, "%d.%m.%Y")),
      "legal_form" => letter.legal_form,
      "submission_to" => letter.submission_to,
      "certificate_purpose" => letter.certificate_purpose,
      "signing_location" => letter.signing_location || letter.sender_city
    }
  end

  defp verify_pdf_upload(%{body: <<"%PDF-", _rest::binary>>, filename: filename})
       when is_binary(filename) and filename != "", do: :ok

  defp verify_pdf_upload(_upload), do: {:error, :letter_document_must_be_a_pdf}

  defp outgoing_letter_document_filename(letter, filename) do
    "letter-#{letter.id}-#{Path.basename(filename)}"
  end

  defp letter_document_title(%Letter{subject: subject}) when is_binary(subject) and subject != "", do: subject
  defp letter_document_title(%Letter{}), do: "Letter document"

  defp uploaded_letter_subject(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[_-]+/, " ")
    |> String.trim()
    |> case do
      "" -> "Uploaded letter"
      subject -> subject
    end
  end

  defp prepare_uploaded_letter_document(%Letter{kind: "uploaded_letter"} = letter) do
    with document_id when is_binary(document_id) <- letter.document_id,
         {:ok, document} <- Documents.process_document(document_id, classify_fallback?: true),
         {:ok, letter} <- associate_uploaded_letter_account(letter, document) do
      {:ok, letter}
    else
      nil -> {:error, :letter_document_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp prepare_uploaded_letter_document(letter), do: {:ok, letter}

  defp associate_uploaded_letter_account(letter, %{account_id: nil}), do: {:ok, letter}

  defp associate_uploaded_letter_account(%Letter{account_id: account_id} = letter, %{account_id: account_id}),
    do: {:ok, letter}

  defp associate_uploaded_letter_account(letter, %{account_id: account_id}) do
    case Accounts.get_account(account_id) do
      %Account{} = account ->
        attrs = %{account_id: account.id}

        with {:ok, updated} <- update_letter(letter, attrs),
             :ok <-
               audit(
                 "letter.account_associated",
                 updated,
                 letter.created_by,
                 %{
                   "account_id" => account.id,
                   "path" => "/commercial/sales/accounts/#{account.id}"
                 },
                 interface: "worker"
               ) do
          {:ok, updated}
        end

      nil ->
        {:ok, letter}
    end
  end

  defp insert_letter(letter, document) do
    letter
    |> Map.put(:document_id, document.id)
    |> Letter.changeset(%{})
    |> Repo.insert()
  end

  defp enqueue_send(letter) do
    %{letter_id: letter.id}
    |> SendLetter.new()
    |> Oban.insert()
  end

  defp enqueue_delivery_preparation(letter) do
    %{letter_id: letter.id}
    |> PrepareDelivery.new()
    |> Oban.insert()
  end

  defp do_deliver(letter) do
    with {:ok, sending} <- update_letter(letter, %{status: "sending", last_error: nil}),
         {:ok, pdf} <- load_letter_pdf(sending),
         {:ok, delivery} <- Pingen.send_letter(sending, pdf),
         {:ok, delivered} <- apply_provider_delivery(sending, delivery, "submission") do
      audit(
        "letter.submitted",
        delivered,
        delivered.created_by,
        %{
          "pingen_letter_id" => delivered.pingen_letter_id,
          "pingen_status" => delivered.pingen_status
        },
        interface: "worker"
      )

      {:ok, delivered}
    else
      :disabled -> fail_delivery(letter, :postal_delivery_not_configured)
      {:error, reason} -> fail_delivery(letter, reason)
    end
  end

  defp load_letter_pdf(%Letter{kind: "uploaded_letter", document_id: document_id}) when is_binary(document_id),
    do: load_document_pdf(document_id)

  defp load_letter_pdf(%Letter{signed_document_id: document_id}) when is_binary(document_id),
    do: load_document_pdf(document_id)

  defp load_letter_pdf(_letter), do: {:error, :letter_has_no_document}

  defp load_document_pdf(document_id) do
    with document when not is_nil(document) <- Documents.get_document(document_id, pages: false),
         {:ok, %{body: body}} <- Storage.get_object(document.storage_key) do
      {:ok, body}
    else
      nil -> {:error, :letter_document_not_found}
      {:error, reason} -> {:error, {:letter_document_unavailable, reason}}
    end
  end

  defp apply_provider_delivery(letter, delivery, source) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    next_status = provider_status(delivery.status, letter.status)

    attrs =
      %{
        pingen_letter_id: delivery.id || letter.pingen_letter_id,
        pingen_tracking_number: delivery.tracking_number || letter.pingen_tracking_number,
        pingen_status: delivery.status || letter.pingen_status,
        pingen_events: append_event(letter.pingen_events, provider_event(delivery, source, now)),
        last_checked_at: now,
        status: next_status,
        last_error: nil
      }
      |> Map.merge(provider_status_timestamp_attrs(next_status, delivery, letter, now))

    update_letter(letter, attrs)
  end

  defp apply_webhook(letter, payload) do
    data = payload["data"] || %{}
    attributes = data["attributes"] || %{}
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    next_status = provider_status(data["type"], letter.status)

    attrs =
      %{
        status: next_status,
        pingen_status: data["type"] || letter.pingen_status,
        pingen_events: append_event(letter.pingen_events, webhook_event(data, attributes, now)),
        last_checked_at: now,
        last_error: webhook_last_error(next_status, attributes)
      }
      |> Map.merge(webhook_status_timestamp_attrs(next_status, letter, now))

    update_letter(letter, attrs)
  end

  defp update_letter(letter, attrs) do
    letter
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  defp fail_delivery(letter, reason) do
    case update_letter(letter, %{status: "failed", last_error: inspect(reason), last_checked_at: DateTime.utc_now()}) do
      {:ok, failed} ->
        audit("letter.delivery_failed", failed, failed.created_by, %{"reason" => inspect(reason)}, interface: "worker")
        {:error, reason}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp webhook_letter_id(%{"data" => %{"relationships" => relationships}}) when is_map(relationships) do
    case get_in(relationships, ["letter", "data", "id"]) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :missing_letter_id}
    end
  end

  defp webhook_letter_id(_payload), do: {:error, :missing_letter_id}

  defp provider_status(provider_status, current_status) do
    current_status = current_status || "queued"

    cond do
      current_status in ["delivered", "undeliverable"] -> current_status
      provider_status in ["webhook_delivered", "delivered"] -> "delivered"
      provider_status in ["webhook_undeliverable", "undeliverable"] -> "undeliverable"
      provider_status in ["webhook_sent", "sent", "submitted", "dispatched"] -> "sent"
      provider_status in ["webhook_issues", "failed", "error", "cancelled"] -> "failed"
      true -> "sending"
    end
  end

  defp provider_status_timestamp_attrs("sent", delivery, letter, now),
    do: %{sent_at: delivery.submitted_at || letter.sent_at || now}

  defp provider_status_timestamp_attrs("delivered", delivery, letter, now),
    do: %{delivered_at: delivery.delivered_at || letter.delivered_at || now}

  defp provider_status_timestamp_attrs("undeliverable", delivery, letter, now),
    do: %{undeliverable_at: delivery.undeliverable_at || letter.undeliverable_at || now}

  defp provider_status_timestamp_attrs(_status, _delivery, _letter, _now), do: %{}

  defp webhook_status_timestamp_attrs("sent", letter, now), do: %{sent_at: letter.sent_at || now}
  defp webhook_status_timestamp_attrs("delivered", letter, now), do: %{delivered_at: letter.delivered_at || now}

  defp webhook_status_timestamp_attrs("undeliverable", letter, now),
    do: %{undeliverable_at: letter.undeliverable_at || now}

  defp webhook_status_timestamp_attrs(_status, _letter, _now), do: %{}
  defp webhook_last_error("failed", attributes), do: attributes["reason"]
  defp webhook_last_error(_status, _attributes), do: nil

  defp provider_event(delivery, source, now) do
    %{
      "id" => "#{source}:#{delivery.id || "pending"}:#{delivery.status || "unknown"}",
      "type" => delivery.status || "unknown",
      "source" => source,
      "occurred_at" => DateTime.to_iso8601(now),
      "data" => delivery.raw || %{}
    }
  end

  defp webhook_event(data, attributes, now) do
    %{
      "id" => data["id"] || "webhook:#{DateTime.to_unix(now, :microsecond)}",
      "type" => data["type"] || "unknown",
      "source" => "webhook",
      "occurred_at" => attributes["created_at"] || DateTime.to_iso8601(now),
      "reason" => attributes["reason"]
    }
  end

  defp append_event(events, event) do
    items = if is_list(events["items"]), do: events["items"], else: []

    if Enum.any?(items, &(&1["id"] == event["id"])) do
      %{"items" => items}
    else
      %{"items" => Enum.take([event | items], 50)}
    end
  end

  defp maybe_filter_account(query, account_id) when is_binary(account_id),
    do: where(query, [letter], letter.account_id == ^account_id)

  defp maybe_filter_account(query, _account_id), do: query
  defp preload_letter(nil), do: nil

  defp preload_letter(letter),
    do:
      Repo.preload(letter, [:account, :document, :signed_document, :created_by, :confirmed_by, :signed_uploaded_by],
        force: true
      )

  defp require_configured do
    if Config.configured?(), do: :ok, else: :disabled
  end

  defp authorize(actor) do
    if Users.executive?(actor), do: :ok, else: {:error, :unauthorized}
  end

  defp audit(action, letter, actor, metadata, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "letter",
        target_id: letter.id,
        target_label: letter.subject,
        metadata:
          Map.merge(
            %{
              "account_id" => letter.account_id,
              "document_id" => letter.document_id,
              "signed_document_id" => letter.signed_document_id,
              "kind" => letter.kind,
              "status" => letter.status,
              "path" => "/commercial/sales/accounts/#{letter.account_id}"
            },
            metadata
          )
      },
      audit_options(actor, opts)
    )
  end

  defp audit_options(actor, opts) do
    [actor: actor]
    |> then(fn options ->
      case Keyword.fetch(opts, :interface) do
        {:ok, interface} -> Keyword.put(options, :interface, interface)
        :error -> options
      end
    end)
  end
end
