defmodule Tuist.OAuth.Clients do
  @moduledoc """
  Custom OAuth clients adapter for Boruta that loads client configuration from environment
  instead of the database, similar to how TokenGenerator was reimplemented.

  This adapter implements both Boruta.Oauth.Clients and Boruta.Openid.Clients behaviors
  to provide OAuth client information from environment configuration.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Boruta.Oauth.Clients
  alias Tuist.Environment

  @impl Clients
  def get_client(client_id) do
    client = tuist_oauth_client()

    if client_id == client.id do
      client
    else
      {:error, :not_found}
    end
  end

  @impl Clients
  def public! do
    {:error, :not_found}
  end

  @impl Clients
  def authorized_scopes(_client) do
    []
  end

  @impl Clients
  def get_client_by_did(_did) do
    {:error, "Client lookup by DID not supported"}
  end

  @impl Boruta.Openid.Clients
  def create_client(_registration_params) do
    {:error, "Client creation not supported"}
  end

  @impl Clients
  def list_clients_jwk do
    [tuist_oauth_client()]
    |> Enum.map(fn client ->
      jwk = JOSE.JWK.from_pem(client.jwt_private_key)
      Map.put(jwk, "kid", Boruta.Oauth.Client.Crypto.kid_from_private_key(client.private_key))
      jwk
    end)
    |> Enum.uniq_by(& &1["kid"])
  end

  @impl Boruta.Openid.Clients
  def refresh_jwk_from_jwks_uri(_client_id) do
    {:error, "JWK refresh from JWKS URI not supported"}
  end

  defp tuist_oauth_client do
    %Boruta.Oauth.Client{
      id: Environment.oauth_client_id(),
      secret: Environment.oauth_client_secret(),
      name: Environment.oauth_client_name(),
      access_token_ttl: 86_400,
      authorization_code_ttl: 60,
      refresh_token_ttl: 2_592_000,
      id_token_ttl: 86_400,
      id_token_signature_alg: "RS256",
      userinfo_signed_response_alg: "RS256",
      redirect_uris: ["tuist://oauth-callback"],
      authorize_scope: false,
      supported_grant_types: [
        "client_credentials",
        "password",
        "authorization_code",
        "refresh_token",
        "implicit",
        "revoke",
        "introspect"
      ],
      pkce: true,
      public_refresh_token: false,
      public_revoke: false,
      confidential: false,
      token_endpoint_auth_methods: [
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ],
      token_endpoint_jwt_auth_alg: "HS256",
      jwt_public_key: Environment.oauth_jwt_public_key(),
      private_key: Environment.oauth_private_key(),
      enforce_dpop: false
    }
  end
end
