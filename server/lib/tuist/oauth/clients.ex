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

  @authorization_code_ttl 300
  @supported_grant_types ["authorization_code", "refresh_token", "revoke"]

  @impl Clients
  def get_client(client_id) do
    case static_client(client_id) do
      %Client{} = client ->
        client

      nil ->
        case EctoClients.get_client(client_id) do
          %Client{} = client -> client |> ensure_authorization_code_ttl() |> restrict_grant_types()
          nil -> nil
        end
    end
  end

  @impl Clients
  def public! do
    (%Client{} = client) = tuist_oauth_client()
    client
  end

  @impl Clients
  def authorized_scopes(%Client{id: client_id} = client) do
    case static_client(client_id) do
      %Client{} -> []
      nil -> EctoClients.authorized_scopes(client)
    end
  end

  @impl Clients
  def get_client_by_did(did) do
    case EctoClients.get_client_by_did(did) do
      %Client{} = client -> restrict_grant_types(client)
      other -> other
    end
  end

  @impl Boruta.Openid.Clients
  def create_client(registration_params) do
    registration_params
    |> Map.put(:authorization_code_ttl, @authorization_code_ttl)
    |> Map.update(:supported_grant_types, @supported_grant_types, &supported_grant_types/1)
    |> EctoClients.create_client()
  end

  @impl Clients
  def list_clients_jwk do
    %Client{} = client = tuist_oauth_client()

    tuist_client_jwk =
      case to_client_jwk(client) do
        nil -> []
        jwk -> [{client, jwk}]
      end

    Enum.uniq_by(tuist_client_jwk ++ EctoClients.list_clients_jwk(), fn {_client, jwk} -> jwk["kid"] end)
  end

  @impl Boruta.Openid.Clients
  def refresh_jwk_from_jwks_uri(client_id) do
    case static_client(client_id) do
      %Client{} -> {:error, "JWK refresh from JWKS URI not supported"}
      nil -> EctoClients.refresh_jwk_from_jwks_uri(client_id)
    end
  end

  defp static_client(client_id) when is_binary(client_id) do
    Enum.find(
      [kura_introspection_client(), tuist_oauth_client()],
      &match?(%Client{id: ^client_id}, &1)
    )
  end

  defp static_client(_client_id), do: nil

  defp android_emulator_redirect_uris do
    base_url = Environment.app_url(path: "/oauth/callback/android")
    uri = URI.parse(base_url)

    cond do
      uri.host in ["localhost", "127.0.0.1"] ->
        [URI.to_string(%{uri | host: "10.0.2.2"})]

      Environment.dev?() ->
        http_config = Application.get_env(:tuist, TuistWeb.Endpoint)[:http] || []
        port = Keyword.get(http_config, :port, 8080)
        ["http://10.0.2.2:#{port}/oauth/callback/android"]

      true ->
        []
    end
  end

  defp tuist_oauth_client do
    %Client{
      id: Environment.oauth_client_id(),
      secret: Environment.oauth_client_secret(),
      name: Environment.oauth_client_name(),
      access_token_ttl: 86_400,
      authorization_code_ttl: @authorization_code_ttl,
      refresh_token_ttl: 2_592_000,
      id_token_ttl: 86_400,
      id_token_signature_alg: "RS256",
      userinfo_signed_response_alg: "RS256",
      redirect_uris:
        [
          "tuist://oauth-callback",
          Environment.app_url(path: "/oauth/callback/android")
        ] ++ android_emulator_redirect_uris(),
      authorize_scope: false,
      supported_grant_types: @supported_grant_types,
      pkce: true,
      # Native apps (PKCE, RFC 8252) can't keep a client secret, so they refresh without one.
      public_refresh_token: true,
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

  defp kura_introspection_client do
    if Environment.kura_control_plane_configured?() do
      %Client{
        id: Environment.kura_control_plane_client_id(),
        secret: Environment.kura_control_plane_client_secret(),
        name: "Kura control plane",
        supported_grant_types: ["introspect", "kura_usage", "kura_registration"],
        confidential: true,
        token_endpoint_auth_methods: [
          "client_secret_basic",
          "client_secret_post"
        ]
      }
    end
  end

  defp to_client_jwk(%Client{private_key: private_key}) when is_binary(private_key) do
    jwk = JOSE.JWK.from_pem(private_key)
    Map.put(jwk, "kid", Boruta.Oauth.Client.Crypto.kid_from_private_key(private_key))
  end

  defp to_client_jwk(_), do: nil

  defp ensure_authorization_code_ttl(%Client{authorization_code_ttl: ttl} = client) when ttl < @authorization_code_ttl do
    %{client | authorization_code_ttl: @authorization_code_ttl}
  end

  defp ensure_authorization_code_ttl(%Client{} = client), do: client

  # Clients registered before registration was restricted still carry Boruta's
  # default grant list, which includes grants Tuist doesn't support.
  defp restrict_grant_types(%Client{supported_grant_types: grant_types} = client) do
    %{client | supported_grant_types: supported_grant_types(grant_types)}
  end

  defp supported_grant_types(grant_types) when is_list(grant_types) do
    Enum.filter(grant_types, &(&1 in @supported_grant_types))
  end

  defp supported_grant_types(_grant_types), do: @supported_grant_types
end
