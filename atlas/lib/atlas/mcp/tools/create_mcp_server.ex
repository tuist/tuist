defmodule Atlas.MCP.Tools.CreateMCPServer do
  @moduledoc "Creates an administrator-managed upstream server."

  use Atlas.MCP.Tool,
    name: "create_mcp_server",
    schema: %{
      "type" => "object",
      "required" => ["name", "url", "authorization_url", "token_url"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "authorization_url" => %{"type" => "string"},
        "token_url" => %{"type" => "string"},
        "registration_url" => %{"type" => "string"},
        "scopes" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "server" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "url" => %{"type" => "string"},
            "read_only" => %{"type" => "boolean"}
          },
          "required" => ["name", "url", "read_only"],
          "additionalProperties" => false
        }
      },
      "required" => ["server"],
      "additionalProperties" => false
    }

  alias Atlas.MCP
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Add a read-only upstream server with per-user authorization. Requires administrator write access. " <>
      "Deployment-managed servers and privileged identity headers cannot be changed here."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Server management tools"),
         {:ok, server} <- MCP.create_server_configuration(server_attrs(args)) do
      {:ok, %{server: %{name: server.name, url: server.url, read_only: server.read_only}}}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not add server: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp server_attrs(args) do
    args
    |> Map.take(~w(name url authorization_url token_url registration_url))
    |> Map.put("scope_list", args |> Map.get("scopes", []) |> Enum.join(" "))
  end
end
