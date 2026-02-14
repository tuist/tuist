defmodule Tuist.OAuth.Clients do
  @moduledoc """
  Custom OAuth clients adapter for Boruta that supports both:

  - a static environment-configured client used by Tuist, and
  - dynamically registered clients persisted by Boruta Ecto.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Boruta.Ecto.Clients, as: EctoClients
  alias Boruta.Oauth.Client
  alias Boruta.Oauth.Clients
  alias Tuist.Environment

  @impl Clients
  def get_client(client_id) do
    case tuist_oauth_client() do
      %Client{id: ^client_id} = client -> client
      _ -> EctoClients.get_client(client_id)
    end
  end

  @impl Clients
  def public! do
    case tuist_oauth_client() do
      %Client{} = client -> client
      _ -> EctoClients.public!()
    end
  end

  @impl Clients
  def authorized_scopes(%Client{id: client_id} = client) do
    case tuist_oauth_client() do
      %Client{id: ^client_id} -> []
      _ -> EctoClients.authorized_scopes(client)
    end
  end

  @impl Clients
  def get_client_by_did(did) do
    EctoClients.get_client_by_did(did)
  end

  @impl Boruta.Openid.Clients
  def create_client(registration_params) do
    EctoClients.create_client(registration_params)
  end

  @impl Clients
  def list_clients_jwk do
    tuist_client_jwk =
      case tuist_oauth_client() do
        %Client{} = client ->
          case to_client_jwk(client) do
            nil -> []
            jwk -> [{client, jwk}]
          end

        _ ->
          []
      end

    Enum.uniq_by(tuist_client_jwk ++ EctoClients.list_clients_jwk(), fn {_client, jwk} -> jwk["kid"] end)
  end

  @impl Boruta.Openid.Clients
  def refresh_jwk_from_jwks_uri(client_id) do
    case tuist_oauth_client() do
      %Client{id: ^client_id} -> {:error, "JWK refresh from JWKS URI not supported"}
      _ -> EctoClients.refresh_jwk_from_jwks_uri(client_id)
    end
  end

  defp tuist_oauth_client do
    %Client{
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

  defp to_client_jwk(%Client{private_key: private_key}) when is_binary(private_key) do
    jwk = JOSE.JWK.from_pem(private_key)
    Map.put(jwk, "kid", Boruta.Oauth.Client.Crypto.kid_from_private_key(private_key))
  end

  defp to_client_jwk(_), do: nil
end
