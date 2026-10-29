defmodule Atlas.MCP.Tools.ManageAccountConnections do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "manage_account_connections",
    schema: %{
      "type" => "object",
      "required" => ["action"],
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ["list", "disconnect"]},
        "provider" => %{"type" => "string", "enum" => ["github", "slack", "google"]}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["connections", "settings_url"],
      "properties" => %{
        "settings_url" => %{"type" => "string"},
        "connections" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["provider", "name", "configured", "account_name", "scopes", "status"],
            "properties" => %{
              "provider" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "configured" => %{"type" => "boolean"},
              "account_name" => %{"type" => ["string", "null"]},
              "scopes" => %{"type" => "array", "items" => %{"type" => "string"}},
              "status" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List your personal GitHub, Slack, and Google connections, or disconnect one when explicitly requested. " <>
      "Connecting requires the user to approve OAuth in the browser at settings_url. Never returns credentials."
  end

  # Slack runs as a fixed operator, not the human who sent the message. Either
  # origin signal is sufficient; an omitted audit interface must not bypass it.
  def allowed_context?(%{assigns: %{audit_interface: "slack"}}), do: false
  def allowed_context?(%{assigns: %{mcp_claims: %{"slack_agent" => _}}}), do: false
  def allowed_context?(_conn), do: true

  def execute(conn, args) do
    with true <- allowed_context?(conn),
         :ok <- Tool.authorize_authenticated(conn, "Account connections"),
         :ok <- perform(Tool.current_user(conn), args) do
      {:ok,
       %{
         connections: Connections.list(Tool.current_user(conn)),
         settings_url: AtlasWeb.Endpoint.url() <> "/settings/connections"
       }}
    else
      false -> {:error, "Personal account connections are unavailable to shared Slack identities."}
      error -> error
    end
  end

  defp perform(_user, %{"action" => "list"}), do: :ok

  defp perform(user, %{"action" => "disconnect", "provider" => provider}) when provider in ~w(github slack google) do
    case Connections.disconnect(user, provider) do
      {:ok, :ok} -> :ok
      {:error, _} -> {:error, "Could not disconnect your account."}
    end
  end

  defp perform(_user, _args), do: {:error, "Provide action=list or action=disconnect with a provider."}
end
