defmodule Atlas.MCP.Tools.ListOutreachContacts do
  @moduledoc """
  Lists contacts enrolled in LinkedIn outreach.
  """

  use Atlas.MCP.Tool,
    name: "list_outreach_contacts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => Atlas.Accounts.Contact.outreach_statuses()},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.list_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do: "List account contacts enrolled in LinkedIn outreach, optionally filtered by stage or search text."

  def execute(_conn, args) do
    {contacts, _meta} =
      Outreach.list_contacts(
        query: args["query"],
        status: args["status"],
        limit: args["limit"] || 25
      )

    {:ok, OutreachSerializer.list_response(contacts)}
  end
end
