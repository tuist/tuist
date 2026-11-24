defmodule TuistWeb.Oauth.OpenidController do
  @moduledoc """
  The OpenID Provider surface: metadata (OpenID Connect Discovery 1.0), the
  ID token signing keys (RFC 7517) and the userinfo endpoint (OpenID Connect
  Core 1.0, section 5.3). It exists only while `Environment.oidc_signing_key/0`
  is configured; without it every action answers 404, since this server could
  not sign the ID tokens the metadata promises.
  """
  use TuistWeb, :controller

  alias Boruta.Oauth.Authorization.AccessToken
  alias Boruta.Oauth.BearerToken
  alias Boruta.Oauth.Scope
  alias Boruta.Oauth.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients

  plug :require_provider

  def openid_configuration(conn, _params) do
    issuer = Environment.app_url(route_type: :app)

    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(%{
      issuer: issuer,
      authorization_endpoint: "#{issuer}/oauth2/authorize",
      token_endpoint: "#{issuer}/oauth2/token",
      userinfo_endpoint: "#{issuer}/oauth2/userinfo",
      jwks_uri: "#{issuer}/oauth2/jwks",
      revocation_endpoint: "#{issuer}/oauth2/revoke",
      scopes_supported: Clients.oidc_scopes(),
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      token_endpoint_auth_methods_supported: ["client_secret_basic", "client_secret_post"],
      code_challenge_methods_supported: ["S256"],
      claims_supported: [
        "sub",
        "iss",
        "aud",
        "exp",
        "iat",
        "auth_time",
        "nonce",
        "email",
        "email_verified",
        "name",
        "preferred_username"
      ],
      # Initiating User Registration via OpenID Connect 1.0: `prompt=create`
      # sends a signed-out person to sign up before the authorization continues.
      prompt_values_supported: ["create"]
    })
  end

  def jwks(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(Clients.oidc_jwks())
  end

  # Only tokens granted the `openid` scope reach the claims; any other
  # bearer is refused as the Bearer Token Usage spec (RFC 6750, 3.1) words it.
  def userinfo(conn, _params) do
    with {:ok, value} <- BearerToken.extract_token(conn),
         {:ok, %Token{} = token} <- AccessToken.authorize(value: value),
         {:scope, true} <- {:scope, Scope.contains_openid?(token.scope)},
         # Fails when the user is gone while their token is still live.
         {:ok, claims} <- Token.userinfo(token) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(claims)
    else
      {:scope, false} ->
        bearer_error(conn, :forbidden, "insufficient_scope", "The access token was not granted the openid scope.")

      _ ->
        bearer_error(conn, :unauthorized, "invalid_token", "The access token is invalid or expired.")
    end
  end

  defp bearer_error(conn, status, error, description) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer error="#{error}", error_description="#{description}"))
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end

  defp require_provider(conn, _opts) do
    if Environment.oidc_signing_key() do
      conn
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"}) |> halt()
    end
  end
end
