defmodule Atlas.Inbox.Workers.IngestEmailTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.EmailEventAgent
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.Inbox
  alias Atlas.Inbox.Dkim
  alias Atlas.Inbox.InboxEmail
  alias Atlas.Inbox.Workers.IngestEmail
  alias Atlas.Repo
  alias Atlas.Support.Thread

  setup :verify_on_exit!

  describe "perform/1" do
    test "captures a contact email as a support conversation without the sender allowlist" do
      suffix = System.unique_integer([:positive])

      raw_email = """
      Message-ID: <support-#{suffix}@unknown.example>
      From: Customer <customer-#{suffix}@unknown.example>
      To: contact@tuist.dev
      Subject: Need help

      I need help with my build.
      """

      {:ok, inbox_email} =
        Inbox.persist_inbound(raw_email,
          envelope: %{"from" => "customer-#{suffix}@unknown.example", "to" => "contact@tuist.dev"}
        )

      assert :ok = perform_job(IngestEmail, %{"inbox_email_id" => inbox_email.id})

      reloaded = Repo.get!(InboxEmail, inbox_email.id)
      assert reloaded.status == "processed"
      assert reloaded.outcome["status"] == "support_captured"

      assert %Thread{id: thread_id} = thread = Repo.get!(Thread, reloaded.outcome["support_thread_id"])

      assert thread_id == reloaded.outcome["support_thread_id"]
      assert thread.customer_email == "customer-#{suffix}@unknown.example"
    end

    test "runs the ingest pipeline for an authorized email and records the outcome" do
      account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = """
      Message-ID: <queued-123@acme.example>
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Please schedule renewal planning.
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn email ->
        {:ok, event} =
          Inbox.store_email_event(email, %{
            "account_id" => account.id,
            "title" => "Renewal planning email",
            "summary" => "Maya asked for renewal planning.",
            "matched_on" => %{"type" => "primary_domain", "value" => "acme.example"}
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end)

      {:ok, inbox_email} =
        Inbox.persist_inbound(raw_email,
          envelope: %{"from" => "maya@acme.example", "to" => "inbox@atlas.tuist.dev"}
        )

      assert :ok = perform_job(IngestEmail, %{"inbox_email_id" => inbox_email.id})

      assert [%Event{} = event] = Repo.all(Event)
      assert event.account_id == account.id

      reloaded = Repo.get!(InboxEmail, inbox_email.id)
      assert reloaded.status == "processed"
      assert reloaded.outcome["status"] == "captured"
      assert reloaded.outcome["event_id"] == event.id
      assert reloaded.processed_at

      assert Repo.get_by!(Activity, action: "inbox_email.received", target_id: inbox_email.id).interface == "api"
      assert Repo.get_by!(Activity, action: "inbox_email.processed", target_id: inbox_email.id).interface == "worker"
    end

    test "marks unauthorized senders as ignored" do
      raw_email = """
      From: attacker@example.com
      To: inbox@atlas.tuist.dev
      Subject: Spoofed

      Hello.
      """

      reject(&EmailEventAgent.run/1)

      {:ok, inbox_email} =
        Inbox.persist_inbound(raw_email,
          envelope: %{"from" => "attacker@example.com", "to" => "inbox@atlas.tuist.dev"}
        )

      assert :ok = perform_job(IngestEmail, %{"inbox_email_id" => inbox_email.id})

      reloaded = Repo.get!(InboxEmail, inbox_email.id)
      assert reloaded.status == "ignored"
      assert reloaded.outcome["reason"] == "unauthorized_sender"
    end

    test "returns {:error, _} on transient agent failure so Oban retries" do
      account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = """
      Message-ID: <transient-123@acme.example>
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Hi.
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)
      stub(EmailEventAgent, :run, fn _email -> {:error, :openai_overloaded} end)

      {:ok, inbox_email} =
        Inbox.persist_inbound(raw_email,
          envelope: %{"from" => "maya@acme.example", "to" => "inbox@atlas.tuist.dev"}
        )

      assert {:error, :openai_overloaded} =
               perform_job(IngestEmail, %{"inbox_email_id" => inbox_email.id})

      reloaded = Repo.get!(InboxEmail, inbox_email.id)
      assert reloaded.status == "failed"
      assert reloaded.last_error =~ "openai_overloaded"

      # account is referenced only to give the agent something to match against
      _ = account
    end

    test "cancels on language model credit-limit failures" do
      _account = insert_account!(%{primary_domain: "acme.example"})

      raw_email = """
      Message-ID: <credit-limit-123@acme.example>
      From: maya@acme.example
      To: inbox@atlas.tuist.dev
      Subject: Renewal planning

      Hi.
      """

      stub(Dkim, :verified_domains, fn _raw -> [] end)

      stub(EmailEventAgent, :run, fn _email ->
        {:error, {:api_error, %{status: 402, body: %{"error" => "credit_limit"}}}}
      end)

      {:ok, inbox_email} =
        Inbox.persist_inbound(raw_email,
          envelope: %{"from" => "maya@acme.example", "to" => "inbox@atlas.tuist.dev"}
        )

      assert {:cancel, :llm_credit_limit} =
               perform_job(IngestEmail, %{"inbox_email_id" => inbox_email.id})

      reloaded = Repo.get!(InboxEmail, inbox_email.id)
      assert reloaded.status == "failed"
      assert reloaded.last_error =~ "credit_limit"
    end

    test "cancels when the inbox_email is missing" do
      assert {:cancel, :not_found} =
               perform_job(IngestEmail, %{"inbox_email_id" => "00000000-0000-0000-0000-000000000000"})
    end

    test "cancels when args are malformed" do
      assert {:cancel, :missing_inbox_email_id} = perform_job(IngestEmail, %{})
    end
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
end
