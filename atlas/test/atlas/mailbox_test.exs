defmodule Atlas.MailboxTest do
  use Atlas.DataCase, async: true

  import Atlas.MailboxFixtures

  alias Atlas.Accounts.Account
  alias Atlas.Mailbox

  describe "list_inbox/1" do
    test "lists inbound support emails with the subject each email carried" do
      thread = insert_support_thread!(%{subject: "Cache misses on CI"})
      first = insert_inbound_message!(thread, %{received_at: ~U[2026-09-20 10:00:00Z]})

      reply =
        insert_inbound_message!(thread, %{
          received_at: ~U[2026-09-21 10:00:00Z],
          metadata: %{"subject" => "Re: Cache misses on CI"}
        })

      assert {[latest, earliest], %{total_count: 2}} = Mailbox.list_inbox()

      assert latest.id == reply.id
      assert latest.subject == "Re: Cache misses on CI"
      assert latest.thread_id == thread.id
      assert latest.from_email == thread.customer_email
      assert latest.to_emails == ["contact@tuist.dev"]
      assert latest.received_at == ~U[2026-09-21 10:00:00Z]

      assert earliest.id == first.id
      assert earliest.subject == "Cache misses on CI"
    end

    test "falls back to the conversation subject for emails received before subjects were recorded" do
      thread = insert_support_thread!(%{subject: "Invoice question"})
      insert_inbound_message!(thread, %{metadata: %{}})

      assert {[entry], _metadata} = Mailbox.list_inbox()
      assert entry.subject == "Invoice question"
    end

    test "excludes replies, notes, and chat messages" do
      thread = insert_support_thread!()
      insert_support_reply!(thread)

      assert {[], %{total_count: 0}} = Mailbox.list_inbox()
    end

    test "names the account the conversation belongs to" do
      account = insert_account!()
      thread = insert_support_thread!(%{account_id: account.id})
      insert_inbound_message!(thread)

      assert {[entry], _metadata} = Mailbox.list_inbox()
      assert entry.account_id == account.id
      assert entry.account_name == account.name
    end

    test "searches by sender and subject" do
      matching = insert_support_thread!(%{customer_email: "ada@lovelace.example", subject: "Registry"})
      other = insert_support_thread!(%{subject: "Something else"})
      insert_inbound_message!(matching)
      insert_inbound_message!(other)

      assert {[%{thread_id: thread_id}], _metadata} = Mailbox.list_inbox(query: "lovelace")
      assert thread_id == matching.id

      assert {[%{thread_id: ^thread_id}], _metadata} = Mailbox.list_inbox(query: "registry")
    end

    test "paginates" do
      thread = insert_support_thread!()
      for _ <- 1..3, do: insert_inbound_message!(thread)

      assert {[_, _], %{current_page: 1, total_pages: 2, total_count: 3}} = Mailbox.list_inbox(page_size: 2)
      assert {[_], %{current_page: 2}} = Mailbox.list_inbox(page_size: 2, page: 2)
    end
  end

  describe "list_outbox/1" do
    test "lists deliveries and support replies together, most recent first" do
      delivery = insert_delivery!(%{inserted_at: ~N[2026-09-20 10:00:00]})
      thread = insert_support_thread!(%{subject: "Cache misses on CI"})
      reply = insert_support_reply!(thread, %{occurred_at: ~U[2026-09-21 10:00:00Z]})

      assert {[support_reply, direct], %{total_count: 2}} = Mailbox.list_outbox()

      assert support_reply.id == reply.id
      assert support_reply.kind == "support_reply"
      assert support_reply.subject == "Re: Cache misses on CI"
      assert support_reply.from_email == "contact@tuist.dev"
      assert support_reply.to_emails == [thread.customer_email]
      assert support_reply.thread_id == thread.id
      assert support_reply.status == "sent"
      assert support_reply.queued_at == ~U[2026-09-21 10:00:00Z]

      assert direct.id == delivery.id
      assert direct.kind == "direct"
      assert direct.to_emails == [delivery.recipient_email]
      assert direct.cc_emails == []
      assert direct.from_email == "contact@tuist.dev"
      assert direct.status == "sent"
      assert direct.queued_at == ~U[2026-09-20 10:00:00Z]
    end

    test "resolves the sender a delivery was sent as" do
      broadcast = insert_broadcast!()
      insert_delivery!(%{kind: "broadcast", broadcast_id: broadcast.id, audience_id: broadcast.audience_id})
      insert_delivery!(%{metadata: %{"from_name" => "Billing", "from_email" => "billing@tuist.dev"}})

      {entries, _metadata} = Mailbox.list_outbox()

      assert %{from_name: "Tuist Team", from_email: "team@tuist.dev", broadcast_id: broadcast_id} =
               Enum.find(entries, &(&1.kind == "broadcast"))

      assert broadcast_id == broadcast.id

      assert %{from_name: "Billing", from_email: "billing@tuist.dev"} =
               Enum.find(entries, &(&1.kind == "direct"))
    end

    test "maps delivery states onto one status vocabulary" do
      insert_delivery!(%{status: "pending", delivered_at: nil})
      insert_delivery!(%{status: "failed", delivered_at: nil, error: ":timeout"})
      thread = insert_support_thread!()
      insert_support_reply!(thread, %{delivery_status: "sending", delivered_at: nil})

      {entries, _metadata} = Mailbox.list_outbox()

      assert entries |> Enum.map(& &1.status) |> Enum.sort() == ["failed", "queued", "queued"]
      assert %{error: ":timeout"} = Enum.find(entries, &(&1.status == "failed"))
    end

    test "leaves out replies delivered through the support chat" do
      thread = insert_support_thread!()
      insert_support_reply!(thread, %{metadata: %{"delivery_channel" => "chat"}})

      assert {[], %{total_count: 0}} = Mailbox.list_outbox()
    end

    test "filters by kind and status" do
      insert_delivery!()
      insert_delivery!(%{kind: "welcome", status: "failed", delivered_at: nil})
      thread = insert_support_thread!()
      insert_support_reply!(thread)

      assert {[%{kind: "support_reply"}], _metadata} = Mailbox.list_outbox(kind: "support_reply")
      assert {[%{kind: "welcome"}], _metadata} = Mailbox.list_outbox(status: "failed")
      assert {entries, _metadata} = Mailbox.list_outbox(kind: {:!=, "direct"})
      assert entries |> Enum.map(& &1.kind) |> Enum.sort() == ["support_reply", "welcome"]
    end

    test "searches recipients and subjects" do
      insert_delivery!(%{recipient_email: "billing@acme.example"})
      insert_delivery!(%{subject: "Contract renewal"})

      assert {[%{to_emails: ["billing@acme.example"]}], _metadata} = Mailbox.list_outbox(query: "acme")
      assert {[%{subject: "Contract renewal"}], _metadata} = Mailbox.list_outbox(query: "renewal")
    end

    test "lists the CC addresses of a direct email and finds it by one" do
      delivery = insert_delivery!(%{cc_emails: ["cto@acme.example", "ops@acme.example"]})
      insert_delivery!()

      assert {[entry], %{total_count: 1}} = Mailbox.list_outbox(query: "ops@acme")
      assert entry.id == delivery.id
      assert entry.to_emails == [delivery.recipient_email]
      assert entry.cc_emails == ["cto@acme.example", "ops@acme.example"]
    end

    test "names the account a direct email was sent for" do
      account = insert_account!()
      insert_delivery!(%{metadata: %{"account_id" => account.id, "body_markdown" => "Hello."}})

      assert {[entry], _metadata} = Mailbox.list_outbox()
      assert entry.account_id == account.id
      assert entry.account_name == account.name
    end
  end

  describe "get_sent_email/1" do
    test "loads a direct email with its body" do
      delivery =
        insert_delivery!(%{
          metadata: %{"body_markdown" => "Your price changes.", "reply_to_email" => "billing@tuist.dev"}
        })

      assert %{id: id, body_markdown: "Your price changes.", reply_to_email: "billing@tuist.dev", template: nil} =
               Mailbox.get_sent_email(delivery.id)

      assert id == delivery.id
    end

    test "loads the CC addresses of a direct email" do
      delivery = insert_delivery!(%{cc_emails: ["cto@acme.example"]})

      assert %{cc_emails: ["cto@acme.example"]} = Mailbox.get_sent_email(delivery.id)
    end

    test "loads a broadcast delivery with the broadcast body and audience" do
      broadcast = insert_broadcast!()

      delivery =
        insert_delivery!(%{
          kind: "broadcast",
          broadcast_id: broadcast.id,
          audience_id: broadcast.audience_id,
          metadata: %{}
        })

      assert %{body_markdown: "# Release notes", audience_name: "Newsletter", reply_to_email: "contact@tuist.dev"} =
               Mailbox.get_sent_email(delivery.id)
    end

    test "names the template of an automated email" do
      delivery = insert_delivery!(%{kind: "transactional", metadata: %{"template" => "newsletter-confirmation"}})

      assert %{template: "newsletter-confirmation", body_markdown: nil} = Mailbox.get_sent_email(delivery.id)
    end

    test "loads a support reply with its body" do
      thread = insert_support_thread!(%{subject: "Registry"})
      reply = insert_support_reply!(thread, %{body: "Try clearing the cache."})

      assert %{
               kind: "support_reply",
               subject: "Re: Registry",
               body_markdown: "Try clearing the cache.",
               thread_id: thread_id
             } =
               Mailbox.get_sent_email(reply.id)

      assert thread_id == thread.id
    end

    test "returns nil for an unknown or invalid id" do
      assert Mailbox.get_sent_email(Ecto.UUID.generate()) == nil
      assert Mailbox.get_sent_email("not-a-uuid") == nil
    end

    test "returns nil for an inbound message" do
      thread = insert_support_thread!()
      message = insert_inbound_message!(thread)

      assert Mailbox.get_sent_email(message.id) == nil
    end
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "account-#{System.unique_integer([:positive])}",
      name: "Acme #{System.unique_integer([:positive])}",
      segment: :customer
    })
    |> Repo.insert!()
  end
end
