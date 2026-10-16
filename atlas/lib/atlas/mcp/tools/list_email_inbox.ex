defmodule Atlas.MCP.Tools.ListEmailInbox do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_email_inbox",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Matches the sender name, sender email, or subject."},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.Mailbox.list_schema(:emails, Atlas.MCP.Serializers.Mailbox.received_email_schema())

  alias Atlas.Mailbox
  alias Atlas.MCP.Serializers.Mailbox, as: MailboxSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List emails received at the Tuist contact address, most recent first. Each email belongs to a support conversation; use get_support_thread with support_thread_id to read it."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "support:read", "Email inbox tools") do
      {entries, metadata} =
        Mailbox.list_inbox(query: args["query"], page: args["page"], page_size: args["page_size"])

      emails = Enum.map(entries, &MailboxSerializer.received_email/1)
      {:ok, %{emails: emails, count: length(emails), total_count: metadata.total_count}}
    end
  end
end
