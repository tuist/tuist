defmodule TuistWeb.WellKnownController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.AgentDiscovery
  alias TuistWeb.AgentSkillsDiscovery
  alias TuistWeb.RequestOrigin

  @openai_apps_challenge_token "YoBqoSMoA-RuEX8RMuCKrLnPCXDYUsYtKg-yjFBHmDQ"
  @mcp_path "/mcp"
  @oauth_token_path "/oauth2/token"
  @oauth_authorize_path "/oauth2/authorize"
  @oauth_introspect_path "/oauth2/introspect"
  @oauth_registration_path "/oauth2/register"
  @oauth_revocation_path "/oauth2/revoke"
  @agent_auth_identity_path "/agent/identity"
  @agent_auth_claim_path "/agent/identity/claim"
  @agent_auth_events_path "/agent/event/notify"
  @mcp_protocol_version "2025-06-18"

  def api_catalog(conn, _params) do
    origin = RequestOrigin.from_conn(conn)
    catalog = AgentDiscovery.api_catalog(origin)

    conn
    |> put_resp_header("content-type", AgentDiscovery.api_catalog_content_type())
    |> put_resp_header("link", AgentDiscovery.api_catalog_link_header_value())
    |> send_resp(:ok, JSON.encode!(catalog))
  end

  def agent_skills_index(conn, _params) do
    json(conn, AgentSkillsDiscovery.index())
  end

  @doc """
  Advertises the package registry for this deployment so the command-line
  interface can configure clients without hardcoding a registry path. Keyed
  by ecosystem so future additions do not require a breaking response change.
  Returns 404 when the deployment exposes no registry.
  """
  def registry_discovery(conn, _params) do
    case Tuist.Registry.url() do
      nil ->
        send_resp(conn, :not_found, "")

      url ->
        login_path = (URI.parse(url).path || "") <> "/login"

        json(conn, %{
          "ecosystems" => %{
            "swift" => %{"url" => url, "loginAPIPath" => login_path}
          }
        })
    end
  end

  def openai_apps_challenge(conn, _params) do
    if Environment.tuist_hosted?() do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:ok, @openai_apps_challenge_token)
    else
      send_resp(conn, :not_found, "")
    end
  end

  @doc """
  Returns the MCP Server Card for agent discovery (SEP-1649).
  """
  def mcp_server_card(conn, _params) do
    server = Tuist.MCP.Server.server()
    origin = RequestOrigin.from_conn(conn)

    capabilities =
      [
        {map_size(server.tools) > 0, :tools},
        {map_size(server.resources) > 0, :resources},
        {map_size(server.prompts) > 0, :prompts}
      ]
      |> Enum.filter(fn {present, _} -> present end)
      |> Map.new(fn {_, name} -> {name, %{listChanged: true}} end)

    card = %{
      version: "1.0",
      protocolVersion: @mcp_protocol_version,
      serverInfo: %{
        name: server.name,
        title: server.title,
        version: server.version
      },
      description: server.description,
      documentationUrl: "#{origin}/en/docs/guides/features/agentic-coding/mcp",
      transport: %{
        type: "streamable-http",
        endpoint: @mcp_path
      },
      capabilities: capabilities,
      authentication: %{
        required: true,
        schemes: ["bearer", "oauth2"]
      },
      instructions: server.instructions,
      tools: ["dynamic"],
      prompts: ["dynamic"]
    }

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET")
    |> put_resp_header("access-control-allow-headers", "Content-Type")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(card)
  end

  @doc """
  Returns OAuth Authorization Server metadata.
  """
  def oauth_authorization_server(conn, _params) do
    issuer = Environment.app_url()

    configuration = %{
      resource: "#{issuer}#{@mcp_path}",
      authorization_servers: [issuer],
      issuer: issuer,
      authorization_endpoint: "#{issuer}#{@oauth_authorize_path}",
      token_endpoint: "#{issuer}#{@oauth_token_path}",
      revocation_endpoint: "#{issuer}#{@oauth_revocation_path}",
      introspection_endpoint: "#{issuer}#{@oauth_introspect_path}",
      registration_endpoint: "#{issuer}#{@oauth_registration_path}",
      jwks_uri: "#{issuer}/.well-known/jwks.json",
      grant_types_supported: [
        "authorization_code",
        "refresh_token",
        "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "urn:workos:agent-auth:grant-type:claim"
      ],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["mcp"],
      bearer_methods_supported: ["header"],
      introspection_endpoint_auth_methods_supported: [
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ],
      token_endpoint_auth_methods_supported: [
        "none",
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ],
      agent_auth: agent_auth_metadata(issuer)
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(configuration)
  end

  def jwks(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(Accounts.agent_auth_service_jwks())
  end

  @doc """
  Returns OAuth Protected Resource metadata.
  """
  def oauth_protected_resource(conn, params) do
    app_url = Environment.app_url()

    case Map.get(params, "resource_path", []) do
      [] ->
        conn
        |> put_resp_content_type("application/json")
        |> json(oauth_protected_resource_metadata(app_url, "", "Tuist"))

      ["mcp"] ->
        conn
        |> put_resp_content_type("application/json")
        |> json(oauth_protected_resource_metadata(app_url, @mcp_path, "Tuist MCP"))

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  @doc """
  Serves the Apple App Site Association file dynamically based on the environment.
  """
  def apple_app_site_association(conn, _params) do
    app_id = get_app_id()

    association = %{
      applinks: %{
        apps: [],
        details: [
          %{
            appID: app_id,
            paths: ["/*/*/previews/*"]
          }
        ]
      }
    }

    json(conn, association)
  end

  def assetlinks(conn, _params) do
    json(conn, [
      %{
        relation: ["delegate_permission/common.handle_all_urls"],
        target: %{
          namespace: "android_app",
          package_name: "dev.tuist.app",
          sha256_cert_fingerprints: android_cert_fingerprints()
        }
      }
    ])
  end

  defp android_cert_fingerprints do
    release = "D9:94:6C:7F:C9:CA:86:91:38:26:7C:21:BC:C9:92:10:91:DB:A7:31:C5:AE:8E:05:30:89:5B:11:94:CF:E2:2D"

    if Environment.prod?() do
      [release]
    else
      [
        release,
        # Debug signing certificate fingerprint used in development builds
        "FE:7D:E5:E6:63:5D:E6:2B:7F:20:C0:2A:E3:B4:1F:81:3A:26:1D:96:2F:E5:57:FF:A1:7F:E2:5B:CF:63:E4:77"
      ]
    end
  end

  defp get_app_id do
    team_id = "U6LC622NKF"

    bundle_id =
      cond do
        Environment.stag?() -> "dev.tuist.app.staging"
        Environment.can?() -> "dev.tuist.app.canary"
        true -> "dev.tuist.app"
      end

    "#{team_id}.#{bundle_id}"
  end

  defp oauth_protected_resource_metadata(resource_identifier, resource_path, resource_name) do
    %{
      resource: "#{resource_identifier}#{resource_path}",
      resource_name: resource_name,
      resource_logo_uri: "#{resource_identifier}/images/tuist_logo_32x32@2x.png",
      resource_documentation: "#{resource_identifier}/en/docs/guides/features/agentic-coding/mcp",
      authorization_servers: [resource_identifier],
      bearer_methods_supported: ["header"],
      scopes_supported: ["mcp"],
      agent_auth: agent_auth_metadata(resource_identifier)
    }
  end

  defp agent_auth_metadata(issuer) do
    %{
      skill: "#{issuer}/auth.md",
      identity_endpoint: "#{issuer}#{@agent_auth_identity_path}",
      claim_endpoint: "#{issuer}#{@agent_auth_claim_path}",
      events_endpoint: "#{issuer}#{@agent_auth_events_path}",
      identity_types_supported: ["anonymous", "identity_assertion", "service_auth"],
      identity_assertion: %{
        assertion_types_supported: ["urn:ietf:params:oauth:token-type:id-jag"]
      },
      events_supported: ["https://schemas.workos.com/events/agent/auth/identity/assertion/revoked"],
      compatibility: %{
        legacy_registration_endpoint: "#{issuer}/agent/auth",
        legacy_claim_endpoint: "#{issuer}/agent/auth/claim"
      }
    }
  end
end
