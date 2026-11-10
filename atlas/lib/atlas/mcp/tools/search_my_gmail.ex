defmodule Atlas.MCP.Tools.SearchMyGmail do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "search_my_gmail",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Gmail search syntax, for example `from:alice newer_than:7d` or `is:unread label:inbox`."
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 25, "description" => "Defaults to 10."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["messages"],
      "properties" => %{
        "messages" => %{"type" => "array", "items" => Atlas.MCP.Tools.GmailSerializers.message_schema()}
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "Search the caller's own Gmail mailbox through their personal Google connection. Returns sender, subject, " <>
      "date and snippet; use get_my_gmail_message for a full body. Requires Gmail access granted in Atlas settings."
  end

  def execute(conn, %{"query" => query} = args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Gmail tools"),
         {:ok, messages} <- Gmail.search(Tool.current_user(conn), query, Map.get(args, "limit", 10)) do
      {:ok, %{messages: messages}}
    else
      {:error, :shared_identity} -> {:error, "Personal Gmail is unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, ManageAccountConnections.connection_error("Gmail", reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}
end
