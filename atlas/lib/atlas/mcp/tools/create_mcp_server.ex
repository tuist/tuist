defmodule Atlas.MCP.Tools.CreateMCPServer do
  @moduledoc "Creates an administrator-managed upstream server."

  use Atlas.MCP.Tool,
    name: "create_mcp_server",
    schema: %{
      "type" => "object",
      "required" => ["name", "url"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "auth_type" => %{"type" => "string", "enum" => ["oauth2", "bearer_token"], "default" => "oauth2"},
        "bearer_token" => %{"type" => "string", "description" => "Shared API key, without the Bearer prefix."},
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
    "Add a read-only upstream server with per-user OAuth (default; requires authorization_url and token_url) " <>
      "or a shared API key (auth_type: bearer_token; requires bearer_token). Shared keys grant all Atlas callers " <>
      "the same upstream access. Requires administrator write access. " <>
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
    |> Map.take(~w(name url auth_type bearer_token authorization_url token_url registration_url))
    |> Map.put("scope_list", args |> Map.get("scopes", []) |> Enum.join(" "))
  end
end
