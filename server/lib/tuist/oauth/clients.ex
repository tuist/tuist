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
  alias Boruta.Oauth.Scope
  alias Tuist.Environment

  @max_service_access_token_ttl 3600

  @impl Clients
  def get_client(client_id) do
    case static_client(client_id) do
      %Client{} = client -> client
      nil -> EctoClients.get_client(client_id)
    end
  end

  def service_client?(client_id) when is_binary(client_id) do
    match?(%Client{}, oauth_service_client(client_id))
  end

  def service_client?(_client_id), do: false

  @impl Clients
  def public! do
    case tuist_oauth_client() do
      %Client{} = client -> client
      _ -> EctoClients.public!()
    end
  end

  @impl Clients
  def authorized_scopes(%Client{id: client_id} = client) do
    case oauth_service_client(client_id) do
      %Client{authorized_scopes: scopes} ->
        scopes

      nil ->
        case static_client(client_id) do
          %Client{} -> []
          nil -> EctoClients.authorized_scopes(client)
        end
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
    case static_client(client_id) do
      %Client{} -> {:error, "JWK refresh from JWKS URI not supported"}
      nil -> EctoClients.refresh_jwk_from_jwks_uri(client_id)
    end
  end

  defp static_client(client_id) when is_binary(client_id) do
    Enum.find(
      [kura_introspection_client(), tuist_oauth_client()] ++ oauth_service_clients(),
      &match?(%Client{id: ^client_id}, &1)
    )
  end

  defp static_client(_client_id), do: nil

  defp oauth_service_client(client_id) do
    Enum.find(oauth_service_clients(), &match?(%Client{id: ^client_id}, &1))
  end

  defp oauth_service_clients do
    Environment.oauth_service_clients()
    |> Enum.map(&oauth_service_client_from_config/1)
    |> Enum.reject(&is_nil/1)
  end

  defp oauth_service_client_from_config(config) when is_map(config) do
    id = Map.get(config, "id") || Map.get(config, :id)
    secret = Map.get(config, "secret") || Map.get(config, :secret)
    name = Map.get(config, "name") || Map.get(config, :name) || id
    configured_ttl = Map.get(config, "access_token_ttl") || Map.get(config, :access_token_ttl) || 300
    access_token_ttl = min(configured_ttl, @max_service_access_token_ttl)
    scopes = service_client_scopes(config)

    if is_binary(id) and is_binary(secret) do
      %Client{
        id: id,
        secret: secret,
        name: name,
        access_token_ttl: access_token_ttl,
        refresh_token_ttl: access_token_ttl,
        supported_grant_types: ["client_credentials"],
        authorize_scope: true,
        authorized_scopes: Enum.map(scopes, &%Scope{name: &1}),
        confidential: true,
        token_endpoint_auth_methods: [
          "client_secret_basic",
          "client_secret_post"
        ]
      }
    end
  end

  defp oauth_service_client_from_config(_config), do: nil

  defp service_client_scopes(config) do
    case Map.get(config, "scopes") || Map.get(config, :scopes) do
      scopes when is_list(scopes) -> Enum.filter(scopes, &is_binary/1)
      _ -> []
    end
  end

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
      authorization_code_ttl: 60,
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
      supported_grant_types: [
        "client_credentials",
        "password",
        "authorization_code",
        "refresh_token",
        "implicit",
        "revoke"
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

  defp kura_introspection_client do
    if Environment.kura_control_plane_configured?() do
      %Client{
        id: Environment.kura_control_plane_client_id(),
        secret: Environment.kura_control_plane_client_secret(),
        name: "Kura control plane",
        supported_grant_types: ["introspect", "kura_usage"],
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
end
