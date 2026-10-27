defmodule Atlas.InboxTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.EmailEventAgent
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Documents.Document
  alias Atlas.Documents.Workers.ProcessDocument
  alias Atlas.Inbox
  alias Atlas.Inbox.Dkim
  alias Atlas.Inbox.EmailParser
  alias Atlas.Inbox.InboxEmail
  alias Atlas.Inbox.Workers.IngestEmail
  alias Atlas.Repo

  describe "verify_signature/4" do
    test "accepts a timestamp-prefixed HMAC signature" do
      body = "Subject: Hello\n\nBody"
      timestamp = "1778160000"
      signature = sign(body, timestamp, "secret")

      assert :ok = Inbox.verify_signature(body, timestamp, signature, "secret")
    end

    test "rejects an invalid signature" do
      body = "Subject: Hello\n\nBody"
      timestamp = "1778160000"

      assert {:error, :invalid_signature} =
               Inbox.verify_signature(body, timestamp, sign(body, timestamp, "other"), "secret")
    end
  end

  describe "domains_aligned?/2" do
    test "aligns an exact domain match" do
      assert Inbox.domains_aligned?("tuist.dev", "tuist.dev")
    end

    test "a parent-domain key aligns with a subdomain sender" do
      assert Inbox.domains_aligned?("eng.tuist.dev", "tuist.dev")
    end

    test "a subdomain key does NOT align with the parent sender" do
      refute Inbox.domains_aligned?("tuist.dev", "eng.tuist.dev")
    end

    test "unrelated and lookalike domains do not align" do
      refute Inbox.domains_aligned?("tuist.dev", "evil.example")
      refute Inbox.domains_aligned?("nottuist.dev", "tuist.dev")
      refute Inbox.domains_aligned?("tuist.dev.evil.example", "tuist.dev")
    end
  end

  describe "authorized_sender?/1" do
    test "authorizes an allowed-domain sender backed by a verified DKIM signature" do
      stub(Dkim, :verified_domains, fn _raw -> ["tuist.dev"] end)

      assert Inbox.authorized_sender?(parse_from("Teammate <teammate@tuist.dev>"))
      assert Inbox.authorized_sender?(parse_from("Teammate@Tuist.DEV"))
    end

    test "rejects an allowed-domain sender with no valid DKIM signature (spoofing)" do
      stub(Dkim, :verified_domains, fn _raw -> [] end)

      refute Inbox.authorized_sender?(parse_from("ceo@tuist.dev"))
    end

    test "rejects an allowed-domain sender whose DKIM domain is not allowed/aligned" do
      stub(Dkim, :verified_domains, fn _raw -> ["evil.example"] end)

      refute Inbox.authorized_sender?(parse_from("ceo@tuist.dev"))
    end

    test "authorizes a subdomain sender via a parent-domain DKIM signature" do
      stub(Dkim, :verified_domains, fn _raw -> ["tuist.dev"] end)

      assert Inbox.authorized_sender?(parse_from("ci@eng.tuist.dev"))
    end

    test "authorizes a sender that matches an account without requiring DKIM" do
      stub(Dkim, :verified_domains, fn _raw -> [] end)
      insert_account!(%{primary_domain: "acme.example"})

      assert Inbox.authorized_sender?(parse_from("buyer@acme.example"))
    end

    test "authorizes a sender from an account subdomain without requiring DKIM" do
      stub(Dkim, :verified_domains, fn _raw -> [] end)
      insert_account!(%{primary_domain: "acme.example"})

      assert Inbox.authorized_sender?(parse_from("buyer@support.acme.example"))
    end

    test "authorizes via the SMTP envelope sender when the From header is absent" do
      stub(Dkim, :verified_domains, fn _raw -> ["tuist.dev"] end)
      email = EmailParser.parse("Subject: Hi\n\nBody", %{"from" => "teammate@tuist.dev"})

      assert Inbox.authorized_sender?(email)
    end

    test "rejects a sender that matches no allowed domain or account" do
      stub(Dkim, :verified_domains, fn _raw -> [] end)

      refute Inbox.authorized_sender?(parse_from("attacker@example.com"))
    end

    test "rejects a malformed sender" do
      stub(Dkim, :verified_domains, fn _raw -> [] end)

      refute Inbox.authorized_sender?(parse_from("not-an-email"))
    end
  end

  describe "find_account/1" do
    test "matches by contact email" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{email: "maya@acme.example"})

      assert %{account: ^account, matched_on: %{"type" => "contact_email", "value" => "maya@acme.example"}} =
               Inbox.find_account(["maya@acme.example"])
    end

    test "matches by primary domain" do
      account = insert_account!(%{primary_domain: "acme.example"})

      assert %{account: ^account, matched_on: %{"type" => "primary_domain"}} =
               Inbox.find_account(["buyer@acme.example"])
    end

    test "matches by primary domain for sender subdomains" do
      account = insert_account!(%{primary_domain: "acme.example"})

      assert %{account: ^account, matched_on: %{"type" => "primary_domain"}} =
               Inbox.find_account(["buyer@support.acme.example"])
    end

    test "returns nil when no account matches" do
      assert nil == Inbox.find_account(["buyer@example.com"])
    end

    test "ignores internal atlas.tuist.dev addresses" do
      _account = insert_account!(%{primary_domain: "atlas.tuist.dev"})

      assert nil == Inbox.find_account(["inbox@atlas.tuist.dev", "buyer@unknown.example"])
    end
  end

  describe "store_email_event/2" do
    test "creates an email timeline event" do
      account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = """
      Message-ID: <store-test-123@acme.example>
      Date: Thu, 07 May 2026 15:30:00 +0200
      From: "Maya Chen" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Can we schedule the renewal planning session?
      """

      email = EmailParser.parse(raw_email, %{"from" => "maya@acme.example", "to" => "inbox@atlas.tuist.dev"})

      params = %{
        "account_id" => account.id,
        "title" => "Renewal planning email",
        "summary" => "Maya asked to schedule a renewal planning session.",
        "markdown" => "## Follow-up\n\nSchedule the session.",
        "participants" => [%{"email" => "maya@acme.example", "name" => "Maya Chen", "role" => "sender"}],
        "occurred_at" => "2026-05-07T13:30:00Z",
        "matched_on" => %{"type" => "contact_email", "value" => "maya@acme.example"}
      }

      assert {:ok, %Event{} = event} = Inbox.store_email_event(email, params)
      assert event.account_id == account.id
      assert event.source == "email"
      assert event.kind == "email"
      assert event.external_id == "message-id:store-test-123@acme.example"
      assert event.title == "Renewal planning email"
      assert event.body =~ "Maya asked to schedule"
      assert event.body =~ "## Follow-up"
      assert event.occurred_at == ~U[2026-05-07 13:30:00Z]
      assert event.metadata["matched_on"] == %{"type" => "contact_email", "value" => "maya@acme.example"}

      assert event.metadata["agent_participants"] == [
               %{"email" => "maya@acme.example", "name" => "Maya Chen", "role" => "sender"}
             ]

      assert event.metadata["envelope"] == %{"from" => "maya@acme.example", "to" => "inbox@atlas.tuist.dev"}
    end

    test "is idempotent for the same message-id" do
      account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = "Message-ID: <idem-123@acme.example>\nFrom: maya@acme.example\n\nHello"
      email = EmailParser.parse(raw_email, %{})
      params = %{"account_id" => account.id, "title" => "T", "summary" => "S"}

      {:ok, event1} = Inbox.store_email_event(email, params)
      {:ok, event2} = Inbox.store_email_event(email, params)

      assert event1.id == event2.id
    end
  end

  describe "list_account_contacts/1" do
    test "returns all contacts for an account ordered by name" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{full_name: "Zara Ali", email: "zara@acme.example"})
      insert_contact!(account, %{full_name: "Aaron Lee", email: "aaron@acme.example"})

      contacts = Inbox.list_account_contacts(account.id)

      assert length(contacts) == 2
      assert Enum.map(contacts, & &1.full_name) == ["Aaron Lee", "Zara Ali"]
    end

    test "returns an empty list when the account has no contacts" do
      account = insert_account!(%{})

      assert [] = Inbox.list_account_contacts(account.id)
    end
  end

  describe "upsert_contact/2" do
    test "creates a new contact when none exists" do
      account = insert_account!(%{primary_domain: "acme.example"})

      assert {:ok, contact} =
               Inbox.upsert_contact(account.id, %{
                 "email" => "maya@acme.example",
                 "full_name" => "Maya Chen",
                 "title" => "Procurement Manager",
                 "notes" => "Key decision-maker on the renewal."
               })

      assert contact.email == "maya@acme.example"
      assert contact.full_name == "Maya Chen"
      assert contact.title == "Procurement Manager"
      assert contact.notes == "Key decision-maker on the renewal."
      assert contact.account_id == account.id
    end

    test "updates an existing contact" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{email: "maya@acme.example", full_name: "Maya"})

      assert {:ok, updated} =
               Inbox.upsert_contact(account.id, %{
                 "email" => "maya@acme.example",
                 "full_name" => "Maya Chen",
                 "title" => "VP Procurement",
                 "notes" => "Now confirmed as VP."
               })

      assert updated.full_name == "Maya Chen"
      assert updated.title == "VP Procurement"
      assert updated.notes == "Now confirmed as VP."
    end

    test "skips internal atlas.tuist.dev addresses" do
      account = insert_account!(%{})

      assert {:ok, :skipped} =
               Inbox.upsert_contact(account.id, %{
                 "email" => "inbox@atlas.tuist.dev",
                 "full_name" => "Inbox"
               })

      assert [] = Inbox.list_account_contacts(account.id)
    end

    test "normalises email to lowercase" do
      account = insert_account!(%{primary_domain: "acme.example"})

      {:ok, contact} =
        Inbox.upsert_contact(account.id, %{
          "email" => "Maya@Acme.EXAMPLE",
          "full_name" => "Maya Chen"
        })

      assert contact.email == "maya@acme.example"
    end
  end

  describe "ingest_email/2" do
    test "captures a matching account email as an account event" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{full_name: "Maya Chen", email: "maya@acme.example"})

      raw_email = """
      Message-ID: <renewal-123@acme.example>
      Date: Thu, 07 May 2026 15:30:00 +0200
      From: "Maya Chen" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Can we schedule the renewal planning session next week?
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn email ->
        assert email.subject == "Renewal planning"

        {:ok, event} =
          Inbox.store_email_event(email, %{
            "account_id" => account.id,
            "title" => "Renewal planning email",
            "summary" => "Maya asked to schedule a renewal planning session next week.",
            "markdown" => "## Follow-up\n\nSchedule the renewal planning session.",
            "participants" => [%{"email" => "maya@acme.example", "name" => "Maya Chen", "role" => "sender"}],
            "occurred_at" => "2026-05-07T13:30:00Z",
            "matched_on" => %{"type" => "contact_email", "value" => "maya@acme.example"}
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end)

      assert {:ok, %Event{} = event} = Inbox.ingest_email(raw_email)
      assert event.account_id == account.id
      assert event.source == "email"
      assert event.kind == "email"
      assert event.external_id == "message-id:renewal-123@acme.example"
      assert event.title == "Renewal planning email"
      assert event.body =~ "Maya asked to schedule"
      assert event.body =~ "## Follow-up"
      assert event.metadata["matched_on"] == %{"type" => "contact_email", "value" => "maya@acme.example"}
      assert [%{"email" => "maya@acme.example"}] = event.metadata["agent_participants"]
    end

    test "stores PDF attachments as account documents after capturing the event" do
      account = insert_account!(%{primary_domain: "acme.example"})
      pdf_body = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"
      encoded_pdf = Base.encode64(pdf_body)

      raw_email = """
      Message-ID: <renewal-pdf-123@acme.example>
      Date: Thu, 07 May 2026 15:30:00 +0200
      From: "Maya Chen" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Signed renewal
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Please find the signed renewal attached.
      --mixed-boundary
      Content-Type: application/pdf; name="signed-renewal.pdf"
      Content-Disposition: attachment; filename="signed-renewal.pdf"
      Content-Transfer-Encoding: base64

      #{encoded_pdf}
      --mixed-boundary--
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn email ->
        {:ok, event} =
          Inbox.store_email_event(email, %{
            "account_id" => account.id,
            "title" => "Signed renewal email",
            "summary" => "Maya sent the signed renewal.",
            "matched_on" => %{"type" => "primary_domain", "value" => "acme.example"}
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end)

      assert {:ok, %Event{} = event} = Inbox.ingest_email(raw_email)

      assert [document] = Repo.all(Document)
      assert document.account_id == account.id
      assert document.source == "email"
      assert document.status == "uploaded"
      assert document.original_filename == "signed-renewal.pdf"
      assert document.content_type == "application/pdf"
      assert document.byte_size == byte_size(pdf_body)
      assert document.attributes["email"]["event_id"] == event.id
      assert document.attributes["email"]["message_id"] == "renewal-pdf-123@acme.example"
      assert document.attributes["email"]["attachment_filename"] == "signed-renewal.pdf"
      assert event.metadata["attachment_document_ids"] == [document.id]

      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => document.id})
    end

    test "does not duplicate attachment documents when the same email is retried" do
      account = insert_account!(%{primary_domain: "acme.example"})
      pdf_body = "%PDF-1.4\n%%EOF\n"

      raw_email = """
      Message-ID: <renewal-pdf-idem@acme.example>
      From: "Maya Chen" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Signed renewal
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Please find the signed renewal attached.
      --mixed-boundary
      Content-Type: application/pdf; name="signed-renewal.pdf"
      Content-Disposition: attachment; filename="signed-renewal.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn email ->
        {:ok, event} =
          Inbox.store_email_event(email, %{
            "account_id" => account.id,
            "title" => "Signed renewal email",
            "summary" => "Maya sent the signed renewal."
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end)

      assert {:ok, %Event{id: event_id}} = Inbox.ingest_email(raw_email)
      document = Repo.one!(Document)
      event = Repo.get!(Event, event_id)

      event
      |> Event.changeset(%{metadata: Map.delete(event.metadata, "attachment_document_ids")})
      |> Repo.update!()

      assert {:ok, %Event{id: ^event_id}} = Inbox.ingest_email(raw_email)

      assert Repo.aggregate(Document, :count) == 1
      assert Repo.get!(Event, event_id).metadata["attachment_document_ids"] == [document.id]
    end

    # Forwards from an internal address to inbox@atlas.tuist.dev (a common way
    # to shove personal PDFs into the library) have no external counterparty
    # for the agent to reason about. Sending them through the LLM only invites
    # the agent to spin without submitting; short-circuit and store the PDFs
    # deterministically.
    test "skips the agent and stores attachments for internal-only forwards" do
      pdf_body = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"

      raw_email = """
      Message-ID: <unassigned-pdf-123@tuist.dev>
      From: "Pedro" <pedro@tuist.dev>
      To: inbox@atlas.tuist.dev
      Subject: Fwd: company document
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Please process this document.
      --mixed-boundary
      Content-Type: application/pdf; name="company-document.pdf"
      Content-Disposition: attachment; filename="company-document.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      stub(Dkim, :verified_domains, fn _raw -> ["tuist.dev"] end)
      reject(&EmailEventAgent.run/1)

      assert {:ok, %{status: :documents_captured, reason: :internal_email, documents: [document]}} =
               Inbox.ingest_email(raw_email)

      document = Repo.get!(Document, document.id)
      assert document.account_id == nil
      assert document.source == "email"
      assert document.status == "uploaded"
      assert document.original_filename == "company-document.pdf"
      assert document.content_type == "application/pdf"
      assert document.byte_size == byte_size(pdf_body)
      assert document.attributes["email"]["event_external_id"] == "message-id:unassigned-pdf-123@tuist.dev"
      assert document.attributes["email"]["message_id"] == "unassigned-pdf-123@tuist.dev"
      assert document.attributes["email"]["routing_reason"] == "internal_email"
      assert document.attributes["email"]["attachment_filename"] == "company-document.pdf"
      assert Repo.aggregate(Event, :count) == 0

      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => document.id})

      assert {:ok, %{status: :documents_captured, documents: [%Document{id: document_id}]}} =
               Inbox.ingest_email(raw_email)

      assert document_id == document.id
      assert Repo.aggregate(Document, :count) == 1
    end

    # Forwarding the same PDF twice — for example replying on the same thread
    # so both the original and the reply CC inbox@atlas.tuist.dev — used to
    # crash on the documents_storage_bucket_storage_key_index unique
    # constraint. The storage key is checksum-derived, so the second insert
    # hit a duplicate row that the message-id-scoped lookup could not see.
    # Deduplicate globally on the unmatched path so the second forward
    # returns the existing document instead of blowing up.
    test "reuses an existing document when the same PDF arrives on a different email" do
      pdf_body = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"

      raw_email_one = """
      Message-ID: <fwd-first@tuist.dev>
      From: "Pedro" <pedro@tuist.dev>
      To: inbox@atlas.tuist.dev
      Subject: Fwd: contract copy
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      First forward.
      --mixed-boundary
      Content-Type: application/pdf; name="contract.pdf"
      Content-Disposition: attachment; filename="contract.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      raw_email_two = """
      Message-ID: <fwd-second@tuist.dev>
      From: "Pedro" <pedro@tuist.dev>
      To: inbox@atlas.tuist.dev
      Subject: Fwd: contract copy (retry)
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Second forward with the same attachment.
      --mixed-boundary
      Content-Type: application/pdf; name="contract.pdf"
      Content-Disposition: attachment; filename="contract.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      stub(Dkim, :verified_domains, fn _raw -> ["tuist.dev"] end)
      reject(&EmailEventAgent.run/1)

      assert {:ok, %{status: :documents_captured, documents: [first]}} = Inbox.ingest_email(raw_email_one)

      assert {:ok, %{status: :documents_captured, documents: [%Document{id: second_id}]}} =
               Inbox.ingest_email(raw_email_two)

      assert second_id == first.id
      assert Repo.aggregate(Document, :count) == 1
    end

    test "returns the stored event when the agent echoes a malformed event id" do
      account = insert_account!(%{primary_domain: "acme.example"})
      insert_contact!(account, %{full_name: "Maya Chen", email: "maya@acme.example"})

      raw_email = """
      Message-ID: <renewal-456@acme.example>
      Date: Thu, 07 May 2026 15:30:00 +0200
      From: "Maya Chen" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Can we schedule the renewal planning session next week?
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn email ->
        {:ok, event} =
          Inbox.store_email_event(email, %{
            "account_id" => account.id,
            "title" => "Renewal planning email",
            "summary" => "Maya asked to schedule a renewal planning session next week."
          })

        {:ok, %{status: "captured", event_id: String.slice(event.id, 0, 35), account_id: event.account_id}}
      end)

      assert {:ok, %Event{} = event} = Inbox.ingest_email(raw_email)
      assert event.account_id == account.id
      assert event.external_id == "message-id:renewal-456@acme.example"
    end

    test "ignores authorized emails that the agent classifies as not_account" do
      _account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = """
      From: "Maya" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Vendor pitch

      Hello.
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn _email ->
        {:ok, %{status: "ignored", reason: "not_account"}}
      end)

      assert {:ignored, :not_account} = Inbox.ingest_email(raw_email)
    end

    test "ignores emails from senders that are not authorized" do
      raw_email = """
      From: attacker@example.com
      To: inbox@atlas.tuist.dev
      Subject: Spoofed

      Hello.
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)
      reject(&EmailEventAgent.run/1)

      assert {:ignored, :unauthorized_sender} = Inbox.ingest_email(raw_email)
    end

    test "propagates agent errors" do
      _account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = "From: maya@acme.example\nTo: inbox@atlas.tuist.dev\n\nHello."

      stub(Dkim, :verified_domains, fn _raw -> [] end)
      stub(EmailEventAgent, :run, fn _email -> {:error, :llm_not_configured} end)

      assert {:error, :llm_not_configured} = Inbox.ingest_email(raw_email)
    end

    # Even for legitimate customer replies, the classifier agent occasionally
    # runs out of turns without submitting a result. When that happens with an
    # attachment on the wire, dropping the PDF is worse than storing it as
    # unmatched: the timeline entry is recoverable later, but a lost PDF is
    # not. Fall back to the unmatched-attachment path so no evidence is lost.
    test "falls back to storing attachments when the agent submits no result" do
      pdf_body = "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n"

      raw_email = """
      Message-ID: <no-result-1@acme.example>
      From: "Maya" <maya@acme.example>
      To: inbox@atlas.tuist.dev
      Subject: Signed renewal
      Content-Type: multipart/mixed; boundary="mixed-boundary"

      --mixed-boundary
      Content-Type: text/plain; charset=UTF-8

      Please find attached.
      --mixed-boundary
      Content-Type: application/pdf; name="signed-renewal.pdf"
      Content-Disposition: attachment; filename="signed-renewal.pdf"
      Content-Transfer-Encoding: base64

      #{Base.encode64(pdf_body)}
      --mixed-boundary--
      """

      _account = insert_account!(%{primary_domain: "acme.example"})

      stub(Dkim, :verified_domains, fn _raw -> [] end)
      stub(EmailEventAgent, :run, fn _email -> {:error, :no_result_submitted} end)

      assert {:ok, %{status: :documents_captured, reason: :agent_no_result, documents: [document]}} =
               Inbox.ingest_email(raw_email)

      document = Repo.get!(Document, document.id)
      assert document.account_id == nil
      assert document.source == "email"
      assert document.original_filename == "signed-renewal.pdf"
      assert document.attributes["email"]["routing_reason"] == "agent_no_result"
      assert Repo.aggregate(Event, :count) == 0
    end
  end

  # Backfill helper for reprocessing inbox_emails rows that landed in `failed`
  # before the agent shortcut / no-result fallback were in place. Only `failed`
  # rows are re-enqueued; `pending` rows can already have an in-flight Oban
  # job, and terminal rows (`processed`, `ignored`) short-circuit inside
  # process_inbound/1 anyway.
  describe "reenqueue_failed/0" do
    test "enqueues IngestEmail for every failed row and skips the rest" do
      failed_one = insert_inbox_email!(%{status: "failed", last_error: ":no_result_submitted"})
      failed_two = insert_inbox_email!(%{status: "failed", last_error: ":no_result_submitted"})
      _processed = insert_inbox_email!(%{status: "processed"})
      _ignored = insert_inbox_email!(%{status: "ignored"})
      _pending = insert_inbox_email!(%{status: "pending"})

      assert %{enqueued: 2} = Inbox.reenqueue_failed()

      assert_enqueued(worker: IngestEmail, args: %{"inbox_email_id" => failed_one.id})
      assert_enqueued(worker: IngestEmail, args: %{"inbox_email_id" => failed_two.id})
      assert Enum.count(all_enqueued(worker: IngestEmail)) == 2
    end

    test "returns zero and enqueues nothing when no rows are failed" do
      _processed = insert_inbox_email!(%{status: "processed"})

      assert %{enqueued: 0} = Inbox.reenqueue_failed()
      assert all_enqueued(worker: IngestEmail) == []
    end
  end

  defp parse_from(from) do
    EmailParser.parse("From: #{from}\nSubject: Test\n\nBody", %{})
  end

  defp sign(body, timestamp, secret) do
    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, [timestamp, ".", body]) |> Base.encode16(case: :lower))
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Acme",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_contact!(account, attrs) do
    defaults = %{
      full_name: "Contact",
      email: "contact@example.com",
      account_id: account.id
    }

    %Contact{}
    |> Contact.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_inbox_email!(attrs) do
    defaults = %{
      raw_email: "From: sender@example.com\nSubject: Test\n\nBody",
      received_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    row =
      defaults
      |> Map.merge(attrs)
      |> InboxEmail.create_changeset()
      |> Repo.insert!()

    status_attrs = Map.take(attrs, [:status, :last_error, :processed_at, :outcome])

    if status_attrs == %{} do
      row
    else
      row
      |> InboxEmail.status_changeset(status_attrs)
      |> Repo.update!()
    end
  end
end
