defmodule Atlas.MCP.Serializers.Mailbox do
  @moduledoc false

  alias Atlas.MCP.Tool

  def received_email(entry) do
    %{
      id: entry.id,
      subject: entry.subject,
      from_name: entry.from_name,
      from_email: entry.from_email,
      to_emails: entry.to_emails,
      cc_emails: entry.cc_emails,
      received_at: Tool.iso8601(entry.received_at),
      support_thread_id: entry.thread_id,
      support_thread_status: entry.thread_status,
      account_id: entry.account_id,
      account_name: entry.account_name
    }
  end

  def received_email_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "subject" => nullable_string(),
        "from_name" => nullable_string(),
        "from_email" => %{"type" => "string"},
        "to_emails" => string_array(),
        "cc_emails" => string_array(),
        "received_at" => nullable_string(),
        "support_thread_id" => %{"type" => "string"},
        "support_thread_status" => %{"type" => "string"},
        "account_id" => nullable_string(),
        "account_name" => nullable_string()
      },
      "required" =>
        ~w(id subject from_name from_email to_emails cc_emails received_at support_thread_id support_thread_status account_id account_name),
      "additionalProperties" => false
    }
  end

  def sent_email(entry) do
    %{
      id: entry.id,
      kind: entry.kind,
      subject: entry.subject,
      from_name: entry.from_name,
      from_email: entry.from_email,
      recipient_name: entry.recipient_name,
      to_emails: entry.to_emails,
      cc_emails: entry.cc_emails,
      status: entry.status,
      error: entry.error,
      provider_message_id: entry.provider_message_id,
      queued_at: Tool.iso8601(entry.queued_at),
      delivered_at: Tool.iso8601(entry.delivered_at),
      account_id: entry.account_id,
      account_name: entry.account_name,
      support_thread_id: entry.thread_id,
      broadcast_id: entry.broadcast_id,
      audience_id: entry.audience_id
    }
  end

  def sent_email_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string", "enum" => Atlas.Mailbox.outbox_kinds()},
        "subject" => %{"type" => "string"},
        "from_name" => nullable_string(),
        "from_email" => nullable_string(),
        "recipient_name" => nullable_string(),
        "to_emails" => string_array(),
        "cc_emails" => string_array(),
        "status" => %{"type" => "string", "enum" => Atlas.Mailbox.outbox_statuses()},
        "error" => nullable_string(),
        "provider_message_id" => nullable_string(),
        "queued_at" => nullable_string(),
        "delivered_at" => nullable_string(),
        "account_id" => nullable_string(),
        "account_name" => nullable_string(),
        "support_thread_id" => nullable_string(),
        "broadcast_id" => nullable_string(),
        "audience_id" => nullable_string()
      },
      "required" =>
        ~w(id kind subject from_name from_email recipient_name to_emails cc_emails status error provider_message_id queued_at delivered_at account_id account_name support_thread_id broadcast_id audience_id),
      "additionalProperties" => false
    }
  end

  def sent_email_with_content(entry) do
    entry
    |> sent_email()
    |> Map.merge(%{
      body_markdown: entry.body_markdown,
      template: entry.template,
      reply_to_email: entry.reply_to_email,
      audience_name: entry.audience_name
    })
  end

  def sent_email_with_content_schema do
    base = sent_email_schema()

    %{
      base
      | "properties" =>
          Map.merge(base["properties"], %{
            "body_markdown" => nullable_string(),
            "template" => nullable_string(),
            "reply_to_email" => nullable_string(),
            "audience_name" => nullable_string()
          }),
        "required" => base["required"] ++ ~w(body_markdown template reply_to_email audience_name)
    }
  end

  def list_schema(key, item_schema) do
    %{
      "type" => "object",
      "properties" => %{
        to_string(key) => %{"type" => "array", "items" => item_schema},
        "count" => %{"type" => "integer"},
        "total_count" => %{"type" => "integer"}
      },
      "required" => [to_string(key), "count", "total_count"],
      "additionalProperties" => false
    }
  end

  defp string_array, do: %{"type" => "array", "items" => %{"type" => "string"}}
  defp nullable_string, do: %{"type" => ["string", "null"]}
end
