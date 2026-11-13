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

  @doc "Caller-facing message for a personal connection that cannot serve a tool call."
  def connection_error(_provider, {:invalid, message}), do: message

  def connection_error(provider, {:provider_rejected, status, reason}),
    do: rejection(provider, status, reason, AtlasWeb.Endpoint.url() <> "/settings/connections")

  def connection_error(provider, reason) do
    settings = AtlasWeb.Endpoint.url() <> "/settings/connections"

    case reason do
      :not_connected -> "Connect your #{provider} account at #{settings} first."
      :insufficient_scope -> "Grant #{provider} access at #{settings} first."
      :needs_authorization -> "Your #{provider} connection expired. Reconnect it at #{settings}."
      :connection_changed -> "Your #{provider} connection changed. Reconnect it at #{settings}."
      :not_found -> "#{provider} could not find that item."
      :rate_limited -> "#{provider} is rate limiting requests. Try again shortly."
      _ -> "#{provider} is unavailable. Try again shortly."
    end
  end

  # Only a 401 that survived a token refresh points at the person's grant; a
  # 403 comes from the API's project or Workspace policy and needs an admin.
  defp rejection(provider, _status, reason, _settings) when reason in ~w(SERVICE_DISABLED accessNotConfigured) do
    "The #{provider} API is not enabled in the Google Cloud project behind Atlas's Google OAuth client " <>
      "(Google: #{reason}). An Atlas administrator has to enable it; reconnecting will not help."
  end

  defp rejection(provider, 401, reason, settings) do
    "#{provider} rejected your Google connection even after refreshing it (Google: HTTP 401 #{reason}). " <>
      "Reconnect it at #{settings}."
  end

  defp rejection(provider, 403, reason, _settings) do
    "#{provider} refused the request (Google: HTTP 403 #{reason}). Your connection is valid, so reconnecting " <>
      "will not help: a Google Workspace policy or the Google Cloud project is blocking it. Ask an Atlas administrator."
  end

  defp rejection(provider, status, reason, _settings),
    do: "#{provider} rejected the request (Google: HTTP #{status} #{reason})."

  defp perform(_user, %{"action" => "list"}), do: :ok

  defp perform(user, %{"action" => "disconnect", "provider" => provider}) when provider in ~w(github slack google) do
    case Connections.disconnect(user, provider) do
      {:ok, :ok} -> :ok
      {:error, _} -> {:error, "Could not disconnect your account."}
    end
  end

  defp perform(_user, _args), do: {:error, "Provide action=list or action=disconnect with a provider."}
end
