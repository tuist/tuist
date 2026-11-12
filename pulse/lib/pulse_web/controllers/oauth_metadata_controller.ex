defmodule PulseWeb.OAuthMetadataController do
  @moduledoc """
  OAuth 2.0 Protected Resource Metadata (RFC 9728) naming the trusted issuer
  as authorization server, so MCP clients can discover where to obtain tokens.
  Served only when an issuer is configured.
  """
  use PulseWeb, :controller

  alias Pulse.Auth.Issuer

  @alert_scopes ~w(alert:read alert:rules:write alert:audit:read alert:evaluate alert:preview alert:import alert:record)

  def show(conn, params) do
    case Issuer.config() do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      config ->
        resource = if params["resource"] == ["mcp"], do: config.audience <> "/mcp", else: config.audience

        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> json(%{
          resource: resource,
          authorization_servers: [config.issuer],
          scopes_supported: ["read", "ingest" | @alert_scopes],
          bearer_methods_supported: ["header"],
          resource_signing_alg_values_supported: ["RS256", "ES256", "EdDSA"]
        })
    end
  end
end
