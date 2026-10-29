defmodule Atlas.MCP.Tools.ListEmailOutbox do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_email_outbox",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Matches the subject, sender, or recipients."},
        "kind" => %{"type" => "string", "enum" => Atlas.Mailbox.outbox_kinds()},
        "status" => %{"type" => "string", "enum" => Atlas.Mailbox.outbox_statuses()},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: Atlas.MCP.Serializers.Mailbox.list_schema(:emails, Atlas.MCP.Serializers.Mailbox.sent_email_schema())

  alias Atlas.Mailbox
  alias Atlas.MCP.Serializers.Mailbox, as: MailboxSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List emails Atlas sent, most recently queued first: broadcasts, direct emails, transactional, welcome, and confirmation emails, and support replies. Use get_sent_email for the body."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "support:read", "Email outbox tools") do
      {entries, metadata} =
        Mailbox.list_outbox(
          query: args["query"],
          kind: args["kind"],
          status: args["status"],
          page: args["page"],
          page_size: args["page_size"]
        )

      emails = Enum.map(entries, &MailboxSerializer.sent_email/1)
      {:ok, %{emails: emails, count: length(emails), total_count: metadata.total_count}}
    end
  end
end
