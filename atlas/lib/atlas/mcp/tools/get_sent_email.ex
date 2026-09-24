defmodule Atlas.MCP.Tools.GetSentEmail do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_sent_email",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string", "description" => "The id of an email from list_email_outbox."}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"email" => Atlas.MCP.Serializers.Mailbox.sent_email_with_content_schema()},
      "required" => ["email"],
      "additionalProperties" => false
    }

  alias Atlas.Mailbox
  alias Atlas.MCP.Serializers.Mailbox, as: MailboxSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Get one email Atlas sent, including its Markdown body, or the template it was rendered from when the body was not recorded."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "support:read", "Email outbox tools") do
      case Mailbox.get_sent_email(args["id"]) do
        nil -> {:error, "Sent email not found."}
        email -> {:ok, %{email: MailboxSerializer.sent_email_with_content(email)}}
      end
    end
  end
end
