defmodule TuistWeb.WellKnownController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Namespace.JWTToken

  @mcp_path "/mcp"
  @oauth_token_path "/oauth2/token"
  @oauth_authorize_path "/oauth2/authorize"
  @oauth_registration_path "/oauth2/register"

  @doc """
  Returns the OpenID configuration for JWT verification.
  """
  def openid_configuration(conn, _params) do
    issuer = JWTToken.issuer()

    configuration = %{
      issuer: issuer,
      jwks_uri: "#{issuer}/.well-known/jwks.json",
      response_types_supported: ["id_token"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      claims_supported: ["iss", "sub", "aud", "exp", "iat"],
      scopes_supported: ["openid"]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(configuration)
  end

  @doc """
  Returns OAuth Authorization Server metadata.
  """
  def oauth_authorization_server(conn, _params) do
    issuer = Environment.app_url()

    configuration = %{
      issuer: issuer,
      authorization_endpoint: "#{issuer}#{@oauth_authorize_path}",
      token_endpoint: "#{issuer}#{@oauth_token_path}",
      registration_endpoint: "#{issuer}#{@oauth_registration_path}",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: [
        "none",
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(configuration)
  end

  @doc """
  Returns OAuth Protected Resource metadata for the MCP endpoint.
  """
  def oauth_protected_resource(conn, %{"resource_path" => ["mcp"]}) do
    app_url = Environment.app_url()

    metadata = %{
      resource: "#{app_url}#{@mcp_path}",
      authorization_servers: [app_url],
      bearer_methods_supported: ["header"],
      scopes_supported: [],
      resource_documentation: "#{app_url}/docs/en/guides/features/agentic-coding/mcp"
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(metadata)
  end

  def oauth_protected_resource(conn, %{"resource_path" => []}) do
    oauth_protected_resource(conn, %{"resource_path" => ["mcp"]})
  end

  def oauth_protected_resource(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  @doc """
  Returns the JSON Web Key Set (JWKS) for verifying JWT signatures.
  """
  def jwks(conn, _params) do
    public_jwk = JWTToken.public_jwk()

    jwks = %{
      keys: [public_jwk]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(jwks)
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
end
