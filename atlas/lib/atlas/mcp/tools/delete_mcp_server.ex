defmodule Atlas.MCP.Tools.DeleteMCPServer do
  @moduledoc "Removes an administrator-managed upstream server and its saved user connections."

  use Atlas.MCP.Tool,
    name: "delete_mcp_server",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{"name" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "deleted" => %{"type" => "boolean"},
        "name" => %{"type" => "string"}
      },
      "required" => ["deleted", "name"],
      "additionalProperties" => false
    }

  alias Atlas.MCP
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Remove an administrator-managed upstream server and its saved user connections. " <>
      "Requires administrator write access; deployment-managed servers cannot be removed."
  end

  def execute(conn, %{"name" => name}) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Server management tools"),
         server when not is_nil(server) <- MCP.get_server_configuration_by_name(name),
         {:ok, _deleted} <- MCP.delete_server_configuration(server.id) do
      {:ok, %{deleted: true, name: name}}
    else
      nil -> {:error, "Administrator-managed server not found."}
      {:error, :not_found} -> {:error, "Administrator-managed server not found."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_conn, _args), do: {:error, "name is required."}
end
