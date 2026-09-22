defmodule Atlas.SupportTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.Mailer
  alias Atlas.Repo
  alias Atlas.Support
  alias Atlas.Support.Message
  alias Atlas.Support.Workers.DeliverChatEmailVerification
  alias Atlas.Support.Workers.DeliverReply
  alias Atlas.Support.Workers.PostNotification
  alias Atlas.Users.User

  setup :verify_on_exit!

  describe "ingest_inbound/2" do
    test "creates a customer conversation and associates a matching account" do
      suffix = System.unique_integer([:positive])
      account = insert_account!("customer-#{suffix}.example")
      {email, inbox_email} = inbound_email!("customer-#{suffix}.example", "account-#{suffix}")

      assert {:ok, %{thread: thread, message: message}} = Support.ingest_inbound(email, inbox_email.id)

      assert thread.account_id == account.id
      assert thread.status == "open"
      assert thread.customer_email == "maya@customer-#{suffix}.example"
      assert message.kind == "inbound"
      assert message.inbox_email_id == inbox_email.id
      assert message.message_id == "account-#{suffix}@customer-#{suffix}.example"

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "inbound_received", "thread_id" => thread.id, "message_id" => message.id}
      )

      {[listed_thread], _meta} = Support.list_threads(status: "open")
      assert listed_thread.id == thread.id
      assert Support.list_thread_counts() == %{"open" => 1, "waiting" => 0, "resolved" => 0}
    end

    test "uses threading headers to reopen the existing conversation" do
      suffix = System.unique_integer([:positive])
      {root_email, root_inbox_email} = inbound_email!("customer-#{suffix}.example", "root-#{suffix}")
      {:ok, %{thread: root_thread}} = Support.ingest_inbound(root_email, root_inbox_email.id)
      actor = insert_user!()
      assert {:ok, resolved_thread} = Support.set_status(root_thread, "resolved", actor)

      raw_reply = """
      Message-ID: <reply-#{suffix}@customer-#{suffix}.example>
      In-Reply-To: <root-#{suffix}@customer-#{suffix}.example>
      References: <root-#{suffix}@customer-#{suffix}.example>
      Date: Thu, 07 May 2026 16:30:00 +0000
      From: Maya Chen <maya@customer-#{suffix}.example>
      To: contact@tuist.dev
      Subject: Re: Build cache question

      I have one more question.
      """

      {:ok, reply_inbox_email} =
        Inbox.persist_inbound(raw_reply,
          envelope: %{"from" => "maya@customer-#{suffix}.example", "to" => "contact@tuist.dev"}
        )

      assert {:ok, %{thread: reply_thread, message: reply_message}} =
               Support.ingest_inbound(EmailParser.parse(raw_reply), reply_inbox_email.id)

      assert reply_thread.id == resolved_thread.id
      assert reply_thread.status == "open"
      assert is_nil(reply_thread.resolved_at)
      assert reply_message.in_reply_to == "root-#{suffix}@customer-#{suffix}.example"
      assert reply_message.references == ["root-#{suffix}@customer-#{suffix}.example"]
      assert length(Support.get_thread(reply_thread.id).messages) == 2
    end

    test "does not duplicate a provider retry with a new raw-email record" do
      suffix = System.unique_integer([:positive])
      {email, first_inbox_email} = inbound_email!("customer-#{suffix}.example", "retry-#{suffix}")
      {:ok, %{thread: thread, message: first_message}} = Support.ingest_inbound(email, first_inbox_email.id)

      {:ok, second_inbox_email} =
        Inbox.persist_inbound(email.raw,
          envelope: %{"from" => "maya@customer-#{suffix}.example", "to" => "contact@tuist.dev"}
        )

      assert {:ok, %{thread: duplicate_thread, message: duplicate_message}} =
               Support.ingest_inbound(email, second_inbox_email.id)

      assert duplicate_thread.id == thread.id
      assert duplicate_message.id == first_message.id
      assert Repo.aggregate(Message, :count) == 1
    end

    test "does not merge a different sender into a known conversation through a copied message identifier" do
      suffix = System.unique_integer([:positive])
      {root_email, root_inbox_email} = inbound_email!("customer-#{suffix}.example", "root-#{suffix}")
      {:ok, %{thread: root_thread}} = Support.ingest_inbound(root_email, root_inbox_email.id)

      forwarded_email = """
      Message-ID: <forwarded-#{suffix}@attacker.example>
      In-Reply-To: <root-#{suffix}@customer-#{suffix}.example>
      References: <root-#{suffix}@customer-#{suffix}.example>
      From: Attacker <attacker-#{suffix}@attacker.example>
      To: contact@tuist.dev
      Subject: Re: Build cache question

      Please route this elsewhere.
      """

      {:ok, forwarded_inbox_email} =
        Inbox.persist_inbound(forwarded_email,
          envelope: %{"from" => "attacker-#{suffix}@attacker.example", "to" => "contact@tuist.dev"}
        )

      assert {:ok, %{thread: forwarded_thread}} =
               Support.ingest_inbound(EmailParser.parse(forwarded_email), forwarded_inbox_email.id)

      refute forwarded_thread.id == root_thread.id
      assert forwarded_thread.customer_email == "attacker-#{suffix}@attacker.example"
    end

    test "recognizes the support address when it is copied on an email" do
      email =
        EmailParser.parse("""
        From: Customer <customer@example.com>
        To: teammate@tuist.dev
        Cc: contact@tuist.dev
        Subject: Copied support request

        Please help.
        """)

      assert Support.support_address?(email)
    end
  end

  describe "receive_chat/1 and receive_chat/2" do
    test "delivers replies in chat until the customer confirms their email" do
      suffix = System.unique_integer([:positive])
      account = insert_account!("customer-#{suffix}.example")

      assert {:ok, %{thread: thread, message: message}} =
               Support.receive_chat(%{
                 "name" => "Maya Chen",
                 "email" => "maya@customer-#{suffix}.example",
                 "body" => "The cache upload has stopped progressing.",
                 "source_url" => "https://tuist.dev/docs/cache"
               })

      assert thread.account_id == nil
      assert thread.subject == "Chat with Tuist Support"
      assert thread.status == "open"

      assert thread.metadata == %{
               "channel" => "chat",
               "email_verified" => false,
               "source_url" => "https://tuist.dev/docs/cache"
             }

      assert message.kind == "chat"
      assert message.sender_name == "Maya Chen"
      assert message.sender_email == "maya@customer-#{suffix}.example"
      assert message.inbox_email_id == nil

      assert message.metadata == %{
               "channel" => "chat",
               "email_verified" => false,
               "source_url" => "https://tuist.dev/docs/cache"
             }

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "chat_received", "thread_id" => thread.id, "message_id" => message.id}
      )

      assert_enqueued(worker: DeliverChatEmailVerification, args: %{"thread_id" => thread.id})

      actor = insert_user!()

      assert {:ok, %{message: chat_reply}} =
               Support.reply(thread, %{"body" => "We are looking into it."}, actor)

      assert chat_reply.delivery_status == "delivered"
      assert chat_reply.delivered_at
      assert chat_reply.metadata["delivery_channel"] == "chat"
      refute_enqueued(worker: DeliverReply, args: %{"message_id" => chat_reply.id})

      assert {:error, :chat_reply_attachments_unsupported} =
               Support.reply(
                 thread,
                 %{
                   "body" => "I have attached the details.",
                   "attachments" => [%{filename: "details.txt", content_type: "text/plain", body: "Details"}]
                 },
                 actor
               )

      token = thread |> Support.chat_email_verification_url() |> URI.parse() |> Map.fetch!(:path) |> Path.basename()

      assert {:ok, confirmed_thread} = Support.confirm_chat_email(token)
      assert confirmed_thread.account_id == account.id
      assert confirmed_thread.metadata["email_verified"]

      assert {:ok, %{message: email_reply}} =
               Support.reply(confirmed_thread, %{"body" => "We are looking into it."}, actor)

      assert email_reply.delivery_status == "queued"
      assert email_reply.metadata["delivery_channel"] == "email"
      assert_enqueued(worker: DeliverReply, args: %{"message_id" => email_reply.id})
    end

    test "sends a generic confirmation email without delivering the visitor's chat content" do
      suffix = System.unique_integer([:positive])

      assert {:ok, %{thread: thread}} =
               Support.receive_chat(%{
                 "email" => "maya-#{suffix}@example.com",
                 "body" => "Our cache upload is blocked."
               })

      expect(Mailer, :deliver, fn email ->
        assert email.subject == "Confirm your email for Tuist Support"
        assert email.text_body =~ "/support/chat/verify/"
        refute email.text_body =~ "Our cache upload is blocked."
        {:ok, %{id: "provider-#{suffix}"}}
      end)

      assert :ok = Support.deliver_chat_email_verification(thread.id)
    end

    test "continues a chat only for the conversation's customer email" do
      suffix = System.unique_integer([:positive])

      {:ok, %{thread: thread}} =
        Support.receive_chat(%{
          "email" => "maya-#{suffix}@customer.example",
          "body" => "The first message."
        })

      assert {:ok, %{thread: updated_thread, message: message}} =
               Support.receive_chat(thread, %{
                 "email" => "maya-#{suffix}@customer.example",
                 "body" => "Here is one more detail."
               })

      assert updated_thread.id == thread.id
      assert updated_thread.status == "open"
      assert message.kind == "chat"
      assert length(Support.get_thread(thread.id).messages) == 2

      assert {:error, :customer_mismatch} =
               Support.receive_chat(thread, %{
                 "email" => "another-#{suffix}@customer.example",
                 "body" => "Please add this to the conversation."
               })
    end
  end

  describe "reply/3" do
    test "queues a threaded reply, changes the queue state, and records an internal note" do
      suffix = System.unique_integer([:positive])
      {email, inbox_email} = inbound_email!("customer-#{suffix}.example", "reply-root-#{suffix}")
      {:ok, %{thread: thread}} = Support.ingest_inbound(email, inbox_email.id)
      actor = insert_user!()

      assert {:ok, %{thread: updated_thread, message: message}} =
               Support.reply(thread, %{"body" => "Thanks, we are looking into it.", "reply_all" => true}, actor)

      assert updated_thread.status == "waiting"
      assert message.kind == "outbound"
      assert message.to_emails == ["maya@customer-#{suffix}.example"]
      assert message.in_reply_to == "reply-root-#{suffix}@customer-#{suffix}.example"
      assert message.references == ["reply-root-#{suffix}@customer-#{suffix}.example"]
      assert_enqueued(worker: DeliverReply, args: %{"message_id" => message.id})

      assert {:ok, note} = Support.add_note(updated_thread, %{"body" => "Customer is on a release deadline."}, actor)
      assert note.kind == "note"

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "note_added", "thread_id" => thread.id, "message_id" => note.id}
      )

      assert {:ok, assigned_thread} = Support.assign(updated_thread, actor.id, actor)
      assert assigned_thread.owner_id == actor.id

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "assigned", "thread_id" => thread.id, "assignee_id" => actor.id}
      )

      assert {:ok, resolved_thread} = Support.set_status(assigned_thread, "resolved", actor)
      assert resolved_thread.status == "resolved"

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "status_changed", "thread_id" => thread.id, "status" => "resolved"}
      )
    end

    test "sends a queued reply at most once" do
      suffix = System.unique_integer([:positive])
      {email, inbox_email} = inbound_email!("customer-#{suffix}.example", "delivery-root-#{suffix}")
      {:ok, %{thread: thread}} = Support.ingest_inbound(email, inbox_email.id)
      actor = insert_user!()
      {:ok, %{message: message}} = Support.reply(thread, %{"body" => "We are investigating."}, actor)

      expect(Mailer, :deliver, fn _email -> {:ok, %{id: "provider-#{suffix}"}} end)

      assert :ok = Support.deliver_reply(message.id)
      assert :ok = Support.deliver_reply(message.id)

      delivered_message = Repo.get!(Message, message.id)
      assert delivered_message.delivery_status == "delivered"
      assert delivered_message.provider_message_id == "provider-#{suffix}"

      assert_enqueued(
        worker: PostNotification,
        args: %{"event" => "reply_delivered", "thread_id" => thread.id, "message_id" => message.id}
      )
    end

    test "persists reply attachments and includes them in the delivered email" do
      suffix = System.unique_integer([:positive])
      {email, inbox_email} = inbound_email!("customer-#{suffix}.example", "attachment-root-#{suffix}")
      {:ok, %{thread: thread}} = Support.ingest_inbound(email, inbox_email.id)
      actor = insert_user!()

      assert {:ok, %{message: message}} =
               Support.reply(
                 thread,
                 %{
                   "body" => "I have attached the requested statement.",
                   "attachments" => [
                     %{
                       filename: "statement.txt",
                       content_type: "text/plain",
                       body: "Statement contents"
                     }
                   ]
                 },
                 actor
               )

      assert [%{"filename" => "statement.txt", "storage_key" => storage_key}] = message.metadata["attachments"]
      assert is_binary(storage_key)

      expect(Mailer, :deliver, fn email ->
        assert [attachment] = email.attachments
        assert attachment.filename == "statement.txt"
        assert attachment.content_type == "text/plain"
        assert Swoosh.Attachment.get_content(attachment) == "Statement contents"
        {:ok, %{id: "provider-attachment-#{suffix}"}}
      end)

      assert :ok = Support.deliver_reply(message.id)
    end
  end

  defp inbound_email!(domain, message_prefix) do
    raw_email = """
    Message-ID: <#{message_prefix}@#{domain}>
    Date: Thu, 07 May 2026 15:30:00 +0000
    From: Maya Chen <maya@#{domain}>
    To: contact@tuist.dev
    Subject: Build cache question

    Can you help us understand this cache miss?
    """

    {:ok, inbox_email} =
      Inbox.persist_inbound(raw_email, envelope: %{"from" => "maya@#{domain}", "to" => "contact@tuist.dev"})

    {EmailParser.parse(raw_email), inbox_email}
  end

  defp insert_account!(domain) do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{suffix}",
      name: "Support customer #{suffix}",
      primary_domain: domain,
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_user! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.changeset(%{email: "support-agent-#{suffix}@tuist.dev", name: "Support Agent"})
    |> Repo.insert!()
  end
end
