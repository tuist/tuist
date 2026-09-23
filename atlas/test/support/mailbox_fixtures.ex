defmodule Atlas.MailboxFixtures do
  @moduledoc false

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.Delivery
  alias Atlas.Inbox.InboxEmail
  alias Atlas.Repo
  alias Atlas.Support.Message
  alias Atlas.Support.Thread

  def insert_support_thread!(attrs \\ %{}) do
    now = timestamp()

    Repo.insert!(
      struct(
        %Thread{
          customer_email: "customer-#{System.unique_integer([:positive])}@example.com",
          customer_name: "Customer",
          subject: "Question about caching",
          status: "open",
          last_message_at: now,
          last_inbound_at: now
        },
        attrs
      )
    )
  end

  def insert_inbound_message!(%Thread{} = thread, attrs \\ %{}) do
    {received_at, attrs} = Map.pop(attrs, :received_at, timestamp())

    inbox_email =
      Repo.insert!(%InboxEmail{
        raw_email: "Subject: test\r\n\r\nbody",
        envelope_to: "contact@tuist.dev",
        received_at: received_at,
        status: "processed"
      })

    Repo.insert!(
      struct(
        %Message{
          thread_id: thread.id,
          inbox_email_id: inbox_email.id,
          kind: "inbound",
          message_id: "inbound-#{System.unique_integer([:positive])}@example.com",
          sender_name: thread.customer_name,
          sender_email: thread.customer_email,
          to_emails: ["contact@tuist.dev"],
          body: "Hello Tuist.",
          occurred_at: received_at,
          metadata: %{"subject" => thread.subject}
        },
        attrs
      )
    )
  end

  def insert_support_reply!(%Thread{} = thread, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Message{
          thread_id: thread.id,
          kind: "outbound",
          message_id: "reply-#{System.unique_integer([:positive])}@tuist.dev",
          sender_name: "Tuist Support",
          sender_email: "contact@tuist.dev",
          to_emails: [thread.customer_email],
          body: "Thanks for reaching out.",
          delivery_status: "delivered",
          occurred_at: timestamp(),
          delivered_at: timestamp(),
          metadata: %{"delivery_channel" => "email"}
        },
        attrs
      )
    )
  end

  def insert_delivery!(attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Delivery{
          kind: "direct",
          recipient_email: "recipient-#{System.unique_integer([:positive])}@example.com",
          subject: "Your Tuist pricing is changing",
          status: "delivered",
          delivered_at: timestamp(),
          metadata: %{"body_markdown" => "Your price changes next month."}
        },
        attrs
      )
    )
  end

  def insert_broadcast!(attrs \\ %{}) do
    audience =
      Repo.insert!(%Audience{
        name: "Newsletter",
        slug: "newsletter-#{System.unique_integer([:positive])}"
      })

    Repo.insert!(
      struct(
        %Broadcast{
          audience_id: audience.id,
          subject: "What's new in Tuist",
          body_markdown: "# Release notes",
          from_name: "Tuist Team",
          from_email: "team@tuist.dev",
          reply_to_email: "contact@tuist.dev",
          status: "sent"
        },
        attrs
      )
    )
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
