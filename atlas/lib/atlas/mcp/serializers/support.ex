defmodule Atlas.MCP.Serializers.Support do
  @moduledoc false

  alias Atlas.MCP.Tool
  alias Atlas.Support.Message
  alias Atlas.Support.Thread

  def thread(%Thread{} = thread, opts \\ []) do
    include_messages = Keyword.get(opts, :include_messages, false)

    %{
      id: thread.id,
      subject: thread.subject,
      status: thread.status,
      customer: %{
        name: thread.customer_name,
        email: thread.customer_email,
        account_id: thread.account_id,
        account_name: thread.account && thread.account.name
      },
      owner: owner(thread.owner),
      last_message_at: Tool.iso8601(thread.last_message_at),
      last_inbound_at: Tool.iso8601(thread.last_inbound_at),
      resolved_at: Tool.iso8601(thread.resolved_at),
      messages: if(include_messages, do: Enum.map(thread.messages, &message/1), else: [])
    }
  end

  def message(%Message{} = message) do
    %{
      id: message.id,
      kind: message.kind,
      sender_name: message.sender_name,
      sender_email: message.sender_email,
      recipients: message.to_emails,
      copied_recipients: message.cc_emails,
      body: message.body,
      delivery_status: message.delivery_status,
      occurred_at: Tool.iso8601(message.occurred_at),
      author: owner(message.author),
      attachments: attachments(message)
    }
  end

  def thread_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "subject" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "customer" => customer_schema(),
        "owner" => owner_schema(),
        "last_message_at" => %{"type" => "string"},
        "last_inbound_at" => %{"type" => ["string", "null"]},
        "resolved_at" => %{"type" => ["string", "null"]},
        "messages" => %{"type" => "array", "items" => message_schema()}
      },
      "required" => [
        "id",
        "subject",
        "status",
        "customer",
        "owner",
        "last_message_at",
        "last_inbound_at",
        "resolved_at",
        "messages"
      ],
      "additionalProperties" => false
    }
  end

  def message_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "sender_name" => %{"type" => ["string", "null"]},
        "sender_email" => %{"type" => ["string", "null"]},
        "recipients" => %{"type" => "array", "items" => %{"type" => "string"}},
        "copied_recipients" => %{"type" => "array", "items" => %{"type" => "string"}},
        "body" => %{"type" => "string"},
        "delivery_status" => %{"type" => ["string", "null"]},
        "occurred_at" => %{"type" => "string"},
        "author" => owner_schema(),
        "attachments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "filename" => %{"type" => "string"},
              "content_type" => %{"type" => ["string", "null"]},
              "byte_size" => %{"type" => ["integer", "null"]}
            },
            "required" => ["filename", "content_type", "byte_size"],
            "additionalProperties" => false
          }
        }
      },
      "required" => [
        "id",
        "kind",
        "sender_name",
        "sender_email",
        "recipients",
        "copied_recipients",
        "body",
        "delivery_status",
        "occurred_at",
        "author",
        "attachments"
      ],
      "additionalProperties" => false
    }
  end

  defp customer_schema do
    %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => ["string", "null"]},
        "email" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "account_name" => %{"type" => ["string", "null"]}
      },
      "required" => ["name", "email", "account_id", "account_name"],
      "additionalProperties" => false
    }
  end

  defp owner_schema do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "email" => %{"type" => "string"}
      },
      "required" => ["id", "name", "email"],
      "additionalProperties" => false
    }
  end

  defp owner(nil), do: nil
  defp owner(%Ecto.Association.NotLoaded{}), do: nil
  defp owner(user), do: %{id: user.id, name: user.name, email: user.email}

  defp attachments(%Message{metadata: metadata}) do
    metadata
    |> Map.get("attachments", [])
    |> Enum.map(fn attachment ->
      %{
        filename: attachment["filename"],
        content_type: attachment["content_type"],
        byte_size: attachment["byte_size"]
      }
    end)
  end
end
