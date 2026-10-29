defmodule Atlas.MCP.Tools.GetMCPConnectionStatus do
  @moduledoc "Live, permission-scoped upstream discovery diagnostics."

  use Atlas.MCP.Tool,
    name: "get_mcp_connection_status",
    schema: %{
      "type" => "object",
      "properties" => %{"server" => %{"type" => "string"}},
      "required" => ["server"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "server" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "message" => %{"type" => "string"},
        "stage" => %{"type" => ["string", "null"]},
        "http_status" => %{"type" => ["integer", "null"]},
        "retryable" => %{"type" => "boolean"},
        "checked_at" => %{"type" => "string"},
        "tools" => %{"type" => "array", "items" => %{"type" => "object"}}
      },
      "required" => ["server", "status", "message", "stage", "http_status", "retryable", "checked_at", "tools"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Check a configured upstream MCP connection (for example grafana) using your current Atlas authorization. " <>
      "Performs fresh tool discovery and returns its permitted schemas or a sanitized failure and recovery action. " <>
      "Use this when upstream tools are missing, and retry after recovery; then refresh the client's tool catalog. " <>
      "Reconnecting the client to Atlas does not reconnect Atlas to the upstream."
  end

  def execute(conn, %{"server" => name}) when is_binary(name) do
    with :ok <- Tool.authorize_authenticated(conn) do
      Proxy.connection_status(conn, name)
    end
  end

  def execute(_conn, _args), do: {:error, "A server name is required."}
end
