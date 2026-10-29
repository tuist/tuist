defmodule Atlas.Inbox do
  @moduledoc """
  Handles inbound email webhooks from the Cloudflare inbox Worker.
  """

  import Ecto.Query

  alias Atlas.Accounts.Agents.EmailEventAgent
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.EventRouting
  alias Atlas.Audit
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Inbox.Dkim
  alias Atlas.Inbox.EmailParser
  alias Atlas.Inbox.InboxEmail
  alias Atlas.Inbox.Workers.IngestEmail
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Support

  require Logger

  def webhook_secret do
    config = Application.get_env(:atlas, :inbox, [])
    Keyword.get(config, :webhook_secret)
  end

  def allowed_sender_domains do
    config = Application.get_env(:atlas, :inbox, [])
    configured_domains = Keyword.get(config, :allowed_sender_domains)

    configured_domains
    |> List.wrap()
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [Application.fetch_env!(:atlas, :allowed_email_domain)]
      domains -> domains
    end
  end

  @doc """
  Authorizes an inbound email by its sender.

  The Cloudflare worker only proves the message came through our relay (HMAC),
  not who sent it, so authenticity is decided here. The visible `From` and the
  SMTP envelope sender are both considered, and a sender is authorized when
  either:

    * a DKIM signature cryptographically verifies and its signing domain is in
      `allowed_sender_domains/0` and aligned with the sender domain. This is
      the spoof-proof path for internal/allowlisted domains, since a forged
      `From: x@tuist.dev` carries no valid tuist.dev signature; or
    * the sender domain matches an existing account. Customer mail is routed by
      account, and account matching already excludes internal domains, so this
      path can never authorize an allowlisted/internal domain on its own.
  """
  def authorized_sender?(email) do
    verified_domains = Dkim.verified_domains(Map.get(email, :raw))

    email
    |> sender_addresses()
    |> Enum.any?(&address_authorized?(&1, verified_domains))
  end

  def verify_timestamp(nil), do: {:error, :stale_timestamp}

  def verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        now = System.system_time(:second)

        if abs(now - ts) < 300 do
          :ok
        else
          {:error, :stale_timestamp}
        end

      _ ->
        {:error, :stale_timestamp}
    end
  end

  def verify_signature(raw_body, timestamp, signature, webhook_secret)
      when is_binary(raw_body) and is_binary(timestamp) and is_binary(webhook_secret) do
    expected =
      "sha256=" <>
        (:crypto.mac(:hmac, :sha256, webhook_secret, [timestamp, ".", raw_body])
         |> Base.encode16(case: :lower))

    if is_binary(signature) and byte_size(signature) == byte_size(expected) and
         Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _timestamp, _signature, _webhook_secret), do: {:error, :invalid_signature}

  @doc """
  Persists a raw inbound email and enqueues an Oban job to process it.

  Called from the request path so the controller can verify HMAC/timestamp
  freshness inside the 5-minute window and then return 200 immediately. The
  Oban worker runs the LLM-backed pipeline with retries, so transient upstream
  failures (OpenAI 5xx, network blips) do not drop messages.
  """
  def persist_inbound(raw_email, opts \\ []) when is_binary(raw_email) do
    envelope = Keyword.get(opts, :envelope, %{})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      raw_email: raw_email,
      envelope_from: Map.get(envelope, "from"),
      envelope_to: Map.get(envelope, "to"),
      received_at: now
    }

    with {:ok, inbox_email} <- attrs |> InboxEmail.create_changeset() |> Repo.insert(),
         {:ok, _job} <- IngestEmail.enqueue(inbox_email.id) do
      Audit.record(
        "inbox_email.received",
        %{
          target_type: "inbox_email",
          target_id: inbox_email.id,
          target_label: "Inbound email",
          metadata: %{
            "received_at" => inbox_email.received_at,
            "raw_email_bytes" => byte_size(raw_email),
            "has_envelope_sender" => present?(inbox_email.envelope_from),
            "has_envelope_recipient" => present?(inbox_email.envelope_to)
          }
        },
        interface: "api"
      )

      {:ok, inbox_email}
    end
  end

  @doc """
  Re-enqueues `IngestEmail` for every inbox_email currently in `failed`.
  Intended as a one-shot backfill after a processing bug is fixed; only
  `failed` rows are touched because they cannot have an in-flight Oban job.
  """
  def reenqueue_failed do
    ids =
      InboxEmail
      |> where([e], e.status == "failed")
      |> select([e], e.id)
      |> Repo.all()

    Enum.each(ids, &IngestEmail.enqueue/1)

    %{enqueued: length(ids)}
  end

  @doc """
  Processes a persisted inbound email: parses, authorizes the sender, runs the
  LLM agent, and stores derived events and PDF attachments. Records the outcome
  on the `inbox_emails` row.

  Returns `{:ok, outcome}` for terminal outcomes (captured, ignored, documents
  captured) and `{:error, reason}` for transient failures that should be retried.
  """
  def process_inbound(inbox_email_id) when is_binary(inbox_email_id) do
    case Repo.get(InboxEmail, inbox_email_id) do
      nil ->
        {:cancel, :not_found}

      %InboxEmail{status: status} = inbox_email when status in ["processed", "ignored"] ->
        {:ok, inbox_email.outcome || %{}}

      %InboxEmail{} = inbox_email ->
        do_process_inbound(inbox_email)
    end
  end

  defp do_process_inbound(%InboxEmail{} = inbox_email) do
    envelope =
      %{"from" => inbox_email.envelope_from, "to" => inbox_email.envelope_to}
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    email = EmailParser.parse(inbox_email.raw_email, envelope)

    result =
      if Support.support_address?(email) do
        Support.ingest_inbound(email, inbox_email.id)
      else
        ingest_parsed_email(email)
      end

    record_outcome(inbox_email, result)
    result
  end

  def ingest_email(raw_email, opts \\ []) when is_binary(raw_email) do
    envelope = Keyword.get(opts, :envelope, %{})
    email = EmailParser.parse(raw_email, envelope)

    ingest_parsed_email(email)
  end

  defp ingest_parsed_email(email) do
    cond do
      not authorized_sender?(email) ->
        Logger.info("Ignoring inbound inbox email: unauthorized sender")
        {:ignored, :unauthorized_sender}

      internal_only?(email) ->
        # No external counterparty for the agent to reason about — a common
        # shape is "forward personal PDF to inbox@atlas.tuist.dev for the
        # library." Skip the LLM entirely and let the unmatched-attachment
        # path store any PDFs deterministically.
        ingest_ignored_email(email, %{"status" => "ignored", "reason" => "internal_email"})

      true ->
        ingest_authorized_email(email)
    end
  end

  # True when every participant address is either on an allowed sender domain
  # (e.g. tuist.dev) or on atlas.tuist.dev itself. Empty participants counts
  # as internal so a malformed message can't sneak past the shortcut into
  # the LLM path.
  defp internal_only?(email) do
    email
    |> EmailParser.participant_emails()
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> case do
      [] -> true
      addresses -> Enum.all?(addresses, &EventRouting.internal_email?/1)
    end
  end

  defp record_outcome(%InboxEmail{} = inbox_email, result) do
    attrs = outcome_attrs(result)

    result =
      inbox_email
      |> InboxEmail.status_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} = success ->
        audit_inbox_outcome(updated)
        success

      error ->
        error
    end
  end

  defp outcome_attrs({:ok, %{status: :documents_captured, reason: reason, documents: documents}}) do
    %{
      status: "processed",
      processed_at: now(),
      outcome: %{
        "status" => "documents_captured",
        "reason" => to_string(reason),
        "document_ids" => Enum.map(documents, & &1.id)
      },
      last_error: nil
    }
  end

  defp outcome_attrs({:ok, %{thread: thread, message: message}}) do
    %{
      status: "processed",
      processed_at: now(),
      outcome: %{
        "status" => "support_captured",
        "support_thread_id" => thread.id,
        "support_message_id" => message.id
      },
      last_error: nil
    }
  end

  defp outcome_attrs({:ok, %Event{} = event}) do
    %{
      status: "processed",
      processed_at: now(),
      outcome: %{"status" => "captured", "event_id" => event.id},
      last_error: nil
    }
  end

  defp outcome_attrs({:ignored, reason}) do
    %{
      status: "ignored",
      processed_at: now(),
      outcome: %{"status" => "ignored", "reason" => to_string(reason)},
      last_error: nil
    }
  end

  defp outcome_attrs({:error, reason}) do
    %{status: "failed", last_error: inspect(reason)}
  end

  defp outcome_attrs(_other), do: %{status: "failed", last_error: "unknown result"}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp ingest_authorized_email(email) do
    case EmailEventAgent.run(email) do
      {:ok, %{status: "captured"} = result} ->
        with {:ok, event} <- fetch_captured_event(email, result),
             {:ok, documents} <- store_pdf_attachments(email, event) do
          attach_document_ids(event, documents)
        end

      {:ok, %{status: "ignored"} = result} ->
        ingest_ignored_email(email, result)

      # The classifier agent occasionally runs out of turns without submitting
      # a result. Dropping the message with the PDF still attached is worse
      # than storing it as unmatched: the timeline entry is recoverable, but
      # a lost PDF is not. Fall back to the unmatched-attachment path.
      {:error, :no_result_submitted} ->
        Logger.warning("EmailEventAgent submitted no result; storing attachments as unmatched")
        ingest_ignored_email(email, %{"status" => "ignored", "reason" => "agent_no_result"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ingest_ignored_email(email, result) do
    reason = ignored_reason(result)

    with {:ok, documents} <- store_pdf_attachments(email, {:unmatched, reason}) do
      case documents do
        [] ->
          Logger.info("Ignoring inbound inbox email: #{reason}")
          {:ignored, reason}

        documents ->
          Logger.info("Captured inbound inbox email attachments without account: #{reason}")
          {:ok, %{status: :documents_captured, reason: reason, documents: documents}}
      end
    end
  end

  defp ignored_reason(result) do
    case result_value(result, :reason) do
      "internal_email" -> :internal_email
      :internal_email -> :internal_email
      "not_account" -> :not_account
      :not_account -> :not_account
      "agent_no_result" -> :agent_no_result
      :agent_no_result -> :agent_no_result
      _ -> :no_matching_account
    end
  end

  defp fetch_captured_event(email, result) do
    maybe_log_invalid_captured_ids(result)

    event =
      Event
      |> where([event], event.source == "email" and event.external_id == ^external_id(email))
      |> order_by([event], desc: event.inserted_at)
      |> limit(1)
      |> Repo.one()

    case event do
      %Event{} = event -> {:ok, event}
      nil -> {:error, {:invalid_agent_result, result}}
    end
  end

  defp store_pdf_attachments(email, %Event{} = event) do
    store_pdf_attachments(email, event, &find_or_create_attachment_document/3)
  end

  defp store_pdf_attachments(email, {:unmatched, reason}) do
    store_pdf_attachments(email, {:unmatched, reason}, &find_or_create_attachment_document/3)
  end

  defp store_pdf_attachments(email, context, find_or_create) do
    email
    |> EmailParser.pdf_attachments()
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, documents} ->
      case find_or_create.(email, context, attachment) do
        {:ok, %Document{} = document} -> {:cont, {:ok, [document | documents]}}
        {:error, reason} -> {:halt, {:error, {:attachment_document_failed, attachment.filename, reason}}}
      end
    end)
    |> case do
      {:ok, documents} -> {:ok, Enum.reverse(documents)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_or_create_attachment_document(email, %Event{} = event, attachment) do
    case existing_attachment_document(event, attachment) do
      %Document{} = document ->
        {:ok, document}

      nil ->
        Documents.create_from_binary(attachment.body, attachment_document_attrs(email, event, attachment))
    end
  end

  defp find_or_create_attachment_document(email, {:unmatched, reason}, attachment) do
    case existing_attachment_document(email, attachment) do
      %Document{} = document ->
        {:ok, document}

      nil ->
        Documents.create_from_binary(attachment.body, attachment_document_attrs(email, reason, attachment))
    end
  end

  defp existing_attachment_document(%Event{} = event, attachment) do
    Document
    |> where([document], document.source == "email")
    |> where([document], document.account_id == ^event.account_id)
    |> where([document], fragment("?->'email'->>'event_id' = ?", document.attributes, ^event.id))
    |> where(
      [document],
      fragment("?->'email'->>'attachment_checksum_sha256' = ?", document.attributes, ^attachment.checksum_sha256)
    )
    |> Repo.one()
  end

  defp existing_attachment_document(email, attachment) do
    event_external_id = external_id(email)

    match =
      Document
      |> where([document], document.source == "email")
      |> where([document], is_nil(document.account_id))
      |> where([document], fragment("?->'email'->>'event_external_id' = ?", document.attributes, ^event_external_id))
      |> where(
        [document],
        fragment("?->'email'->>'attachment_checksum_sha256' = ?", document.attributes, ^attachment.checksum_sha256)
      )
      |> Repo.one()

    # Same email retrying — return the existing per-message row. Otherwise
    # a different email is forwarding the same PDF (e.g. a reply on the
    # same thread that also CCs inbox). Storage keys are checksum-derived,
    # so inserting again would trip the unique constraint; reuse whatever
    # row already holds those bytes.
    match || existing_attachment_document_by_checksum(attachment)
  end

  defp existing_attachment_document_by_checksum(attachment) do
    Document
    |> where([document], document.source == "email")
    |> where(
      [document],
      fragment("?->'email'->>'attachment_checksum_sha256' = ?", document.attributes, ^attachment.checksum_sha256)
    )
    |> limit(1)
    |> Repo.one()
  end

  defp attachment_document_attrs(email, %Event{} = event, attachment) do
    filename = pdf_document_filename(attachment.filename)

    %{
      "original_filename" => filename,
      "content_type" => "application/pdf",
      "source" => "email",
      "account_id" => event.account_id,
      "uploaded_by_id" => nil,
      "attributes" => %{
        "email" => %{
          "event_id" => event.id,
          "event_external_id" => event.external_id,
          "message_id" => email.message_id,
          "subject" => email.subject,
          "attachment_filename" => attachment.filename,
          "attachment_document_filename" => filename,
          "attachment_content_type" => attachment.content_type,
          "attachment_checksum_sha256" => attachment.checksum_sha256
        }
      }
    }
  end

  defp attachment_document_attrs(email, reason, attachment)
       when reason in [:internal_email, :no_matching_account, :agent_no_result] do
    filename = pdf_document_filename(attachment.filename)

    %{
      "original_filename" => filename,
      "content_type" => "application/pdf",
      "source" => "email",
      "account_id" => nil,
      "uploaded_by_id" => nil,
      "attributes" => %{
        "email" => %{
          "event_external_id" => external_id(email),
          "message_id" => email.message_id,
          "subject" => email.subject,
          "date" => email.date_header,
          "from" => EmailParser.participant_metadata(email.from),
          "to" => EmailParser.participant_metadata(email.to),
          "cc" => EmailParser.participant_metadata(email.cc),
          "reply_to" => EmailParser.participant_metadata(email.reply_to),
          "participants" => EmailParser.participant_metadata(email.participants),
          "routing_reason" => Atom.to_string(reason),
          "attachment_filename" => attachment.filename,
          "attachment_document_filename" => filename,
          "attachment_content_type" => attachment.content_type,
          "attachment_checksum_sha256" => attachment.checksum_sha256
        }
      }
    }
  end

  defp attach_document_ids(event, []), do: {:ok, event}

  defp attach_document_ids(%Event{} = event, documents) do
    document_ids = documents |> Enum.map(& &1.id) |> Enum.uniq()

    metadata =
      event.metadata
      |> Kernel.||(%{})
      |> Map.update("attachment_document_ids", document_ids, fn existing ->
        existing |> List.wrap() |> Kernel.++(document_ids) |> Enum.uniq()
      end)

    event
    |> Event.changeset(%{metadata: metadata})
    |> Repo.update()
    |> tap(fn
      {:ok, updated_event} -> Search.index_account_event(updated_event)
      _result -> :ok
    end)
  end

  defp pdf_document_filename(filename) when is_binary(filename) do
    filename = Path.basename(filename)

    if filename |> String.downcase() |> String.ends_with?(".pdf") do
      filename
    else
      filename <> ".pdf"
    end
  end

  defp pdf_document_filename(_filename), do: "attachment.pdf"

  @doc """
  Finds an Atlas account matching any of the given email addresses.

  Filters out internal (Tuist) addresses, then tries contact email,
  account handle, and primary domain in that order.
  """
  def find_account(emails) when is_list(emails) do
    EventRouting.find_account(emails)
  end

  def find_non_account(emails) when is_list(emails) do
    EventRouting.find_non_account(emails)
  end

  @doc """
  Stores an email as an account timeline event using params supplied by the agent.

  `email` is the parsed email struct (provides metadata and deduplication key).
  `params` is the map from the `store_email_event` tool call:
  `account_id`, `title`, `summary`, `markdown`, `participants`, `occurred_at`, `matched_on`.
  """
  def store_email_event(email, params) do
    occurred_at = resolve_occurred_at(params, email)
    markdown = EmailParser.truncate(params["markdown"] || email.markdown, 16_000)
    summary = resolve_summary(params, email)

    attrs = %{
      "external_id" => external_id(email),
      "source" => "email",
      "kind" => "email",
      "title" => params["title"] || email.subject || "Email conversation",
      "body" => event_body(summary, markdown),
      "occurred_at" => occurred_at,
      "account_id" => params["account_id"],
      "metadata" => %{
        "message_id" => email.message_id,
        "subject" => email.subject,
        "date" => email.date_header,
        "from" => EmailParser.participant_metadata(email.from),
        "to" => EmailParser.participant_metadata(email.to),
        "cc" => EmailParser.participant_metadata(email.cc),
        "reply_to" => EmailParser.participant_metadata(email.reply_to),
        "participants" => EmailParser.participant_metadata(email.participants),
        "agent_participants" => params["participants"] || [],
        "summary" => summary,
        "markdown" => markdown,
        "matched_on" => params["matched_on"],
        "envelope" => email.envelope
      }
    }

    upsert_email_event(attrs)
  end

  @doc """
  Returns all contacts for an account, ordered by name.
  """
  def list_account_contacts(account_id) do
    EventRouting.list_account_contacts(account_id)
  end

  @doc """
  Creates or updates a contact for an account, identified by `(account_id, email)`.

  Skips internal addresses (atlas.tuist.dev and the configured allowed domain).
  `params` keys: `"email"`, `"full_name"`, `"title"` (optional), `"notes"` (optional).
  Returns `{:ok, contact}`, `{:ok, :skipped}`, or `{:error, changeset}`.
  """
  def upsert_contact(account_id, params) do
    EventRouting.upsert_contact(account_id, params)
  end

  defp resolve_occurred_at(params, email) do
    parse_occurred_at(params["occurred_at"]) ||
      email.occurred_at ||
      DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp resolve_summary(params, email) do
    case params["summary"] do
      s when is_binary(s) and s != "" -> s
      _ -> fallback_summary(email)
    end
  end

  defp fallback_summary(%{subject: subject, participants: participants}) do
    participant_count = length(participants)

    if is_binary(subject) and subject != "" do
      "Inbound email captured for this account. Subject: #{subject}. Participants detected: #{participant_count}."
    else
      "Inbound email captured for this account. Participants detected: #{participant_count}."
    end
  end

  defp event_body(summary, nil), do: summary
  defp event_body(summary, ""), do: summary
  defp event_body(summary, markdown), do: summary <> "\n\n---\n\n" <> markdown

  defp upsert_email_event(attrs) do
    case Repo.get_by(Event, source: "email", external_id: attrs["external_id"], account_id: attrs["account_id"]) do
      nil ->
        %Event{}
        |> Event.changeset(attrs)
        |> Repo.insert()
        |> tap(fn
          {:ok, event} ->
            Search.index_account_event(event)

          _ ->
            :ok
        end)

      event ->
        {:ok, event}
    end
  end

  defp external_id(%{message_id: message_id}) when is_binary(message_id) and message_id != "" do
    "message-id:#{message_id}"
  end

  defp external_id(%{raw: raw_email}) do
    "sha256:" <> (:crypto.hash(:sha256, raw_email) |> Base.encode16(case: :lower))
  end

  defp parse_occurred_at(nil), do: nil

  defp parse_occurred_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp sender_addresses(email) do
    from = email.from |> List.wrap() |> Enum.map(& &1.email)
    envelope_from = email.envelope |> Kernel.||(%{}) |> Map.get("from")

    [envelope_from | from]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.uniq()
  end

  defp address_authorized?(address, verified_domains) do
    case EmailParser.email_domain(address) do
      domain when is_binary(domain) and domain != "" ->
        dkim_allowed?(domain, verified_domains) or match?(%{}, EventRouting.find_account([address]))

      _ ->
        false
    end
  end

  defp dkim_allowed?(domain, verified_domains) do
    allowed = allowed_sender_domains()

    Enum.any?(verified_domains, fn signing_domain ->
      signing_domain in allowed and domains_aligned?(domain, signing_domain)
    end)
  end

  @doc """
  Whether a DKIM `signing_domain` may authenticate a `domain` sender.

  Alignment is unidirectional: a key for the sender domain itself or one of its
  parents may sign for it (so `tuist.dev` signs `team.tuist.dev`), but a
  subdomain key must NOT authorize the parent. This is a security boundary: it
  prevents a compromised `evil.tuist.dev` key from forging `tuist.dev` mail.
  """
  def domains_aligned?(domain, signing_domain) do
    domain == signing_domain or String.ends_with?(domain, "." <> signing_domain)
  end

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      domain -> domain
    end
  end

  defp normalize_domain(_domain), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp audit_inbox_outcome(%InboxEmail{} = inbox_email) do
    action =
      case inbox_email.status do
        "processed" -> "inbox_email.processed"
        "ignored" -> "inbox_email.ignored"
        "failed" -> "inbox_email.failed"
      end

    Audit.record(
      action,
      %{
        target_type: "inbox_email",
        target_id: inbox_email.id,
        target_label: "Inbound email",
        metadata: %{
          "status" => inbox_email.status,
          "processed_at" => inbox_email.processed_at,
          "outcome" => inbox_email.outcome || %{}
        }
      },
      interface: "worker"
    )
  end

  defp maybe_log_invalid_captured_ids(result) do
    invalid_ids =
      [event_id: result_value(result, :event_id), account_id: result_value(result, :account_id)]
      |> Enum.reject(fn {_key, value} -> valid_uuid?(value) end)

    if invalid_ids != [] do
      details =
        invalid_ids
        |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

      Logger.warning("email_event_agent returned invalid captured identifiers: #{details}")
    end
  end

  defp result_value(result, key) when is_map(result) do
    Map.get(result, key) || Map.get(result, Atom.to_string(key))
  end

  defp valid_uuid?(nil), do: true
  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Atlas.UUIDv7.cast(value))
  defp valid_uuid?(_value), do: false
end
