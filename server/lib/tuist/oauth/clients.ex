defmodule Tuist.OAuth.Clients do
  @moduledoc """
  Custom OAuth clients adapter for Boruta that supports both:

  - a static environment-configured client used by Tuist,
  - Luft's static client, whose ID is the same on every server,
  - the Luft server's confidential OpenID Connect client, when configured, and
  - dynamically registered clients persisted by Boruta Ecto.
  """

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Boruta.Ecto.Clients, as: EctoClients
  alias Boruta.Oauth.Client
  alias Boruta.Oauth.Client.Crypto
  alias Boruta.Oauth.Clients
  alias Boruta.Oauth.Scope
  alias Tuist.Environment

  @authorization_code_ttl 300
  @loopback_hosts ["127.0.0.1", "::1", "localhost"]
  @forbidden_redirect_schemes ~w(file javascript data vbscript blob ftp)
  @luft_client_id "6653b77b-b787-4eb2-b955-8380ea5f1478"
  @supported_grant_types ["authorization_code", "refresh_token", "revoke"]
  # The OpenID Connect scopes (OIDC Core 5.4).
  @oidc_scopes ["openid", "profile", "email"]
  @organizations_write_scope "account:organizations:write"
  @luft_app_scope "luft:app"
  # App capabilities are separate from project/preview reads and organization
  # creation. None grant access beyond the user's existing permissions.
  @luft_server_scopes @oidc_scopes ++
                        [
                          @organizations_write_scope,
                          @luft_app_scope,
                          "mcp",
                          "account:delete",
                          "account:members:read",
                          "account:sandboxes:write",
                          "account:repositories:read",
                          "account:repositories:write",
                          "project:admin:read",
                          "project:previews:read",
                          "project:previews:write"
                        ]

  @impl Clients
  def get_client(client_id) do
    case static_client(client_id) do
      %Client{} = client ->
        client

      nil ->
        case EctoClients.get_client(client_id) do
          %Client{} = client ->
            client
            |> ensure_authorization_code_ttl()
            |> restrict_grant_types()
            |> restrict_redirect_uris()
            |> Map.put(:pkce, true)

          nil ->
            nil
        end
    end
  end

  @doc """
  Whether `client_id` names a first-party app's client: the Tuist apps' or
  Luft's. Their tokens get the default user scopes when they request none,
  and only clients whose redirect URIs nobody else chooses skip the consent
  page: the Tuist apps'. Luft's redirects can be claimed by other apps, so
  `TuistWeb.Oauth.AuthorizeController` asks for consent anyway.
  """
  def first_party?(client_id) when is_binary(client_id), do: client_id in [Environment.oauth_client_id(), @luft_client_id]

  def first_party?(_client_id), do: false

  @doc """
  Whether a dynamically registered client may use `redirect_uri` (RFC 9700
  section 4.1, RFC 8252 section 7): HTTPS, plain HTTP only on a loopback host,
  or an app's own scheme. Registration is anonymous, so this keeps codes off
  cleartext and local-file targets, and rejecting `*`, which Boruta reads as a
  wildcard, keeps redirect URI matching exact.
  """
  def allowed_redirect_uri?(redirect_uri) when is_binary(redirect_uri) do
    case URI.parse(redirect_uri) do
      %URI{host: host, fragment: nil, scheme: scheme} when is_binary(host) and host != "" and is_binary(scheme) ->
        not String.contains?(redirect_uri, "*") and allowed_redirect_target?(scheme, String.downcase(host))

      _ ->
        false
    end
  end

  def allowed_redirect_uri?(_redirect_uri), do: false

  defp allowed_redirect_target?("https", _host), do: true
  defp allowed_redirect_target?("http", host), do: host in @loopback_hosts
  defp allowed_redirect_target?(scheme, _host), do: scheme not in @forbidden_redirect_schemes

  @doc """
  Luft's client ID. Luft is a first-party app, like the Tuist app: its
  sessions act as the signed-in user (`TuistWeb.Authentication.app_user/1`), so
  new app features need no new scopes and no new sign-in. It is a public native
  client (PKCE, RFC 8252), so the ID is not a secret and is fixed in code, which
  lets Luft sign in to any server running this version without configuration.
  """
  def luft_client_id, do: @luft_client_id

  @doc """
  The Luft server's client ID (`luft.work`), or `nil` when this deployment
  is not configured as its OpenID Provider. It is a confidential client: it
  authenticates to the token endpoint with its secret and gets ID tokens
  signed with `Environment.oidc_signing_key/0`. Unlike the apps, it is not
  first-party: its access tokens hold only the scopes it was granted
  (`luft_server_scopes/0`), because it keeps refresh tokens for everyone who
  signs in (RFC 9700 2.3).
  """
  def luft_server_client_id do
    case luft_server_client() do
      %Client{id: id} -> id
      nil -> nil
    end
  end

  @doc "The OpenID Connect scopes this provider supports."
  def oidc_scopes, do: @oidc_scopes

  @doc "The scopes the Luft server may request."
  def luft_server_scopes, do: @luft_server_scopes

  @doc "The scope that lets an OAuth client create organizations for the user."
  def organizations_write_scope, do: @organizations_write_scope

  @doc "The scope for the configured Luft server's existing app capabilities."
  def luft_app_scope, do: @luft_app_scope

  @impl Clients
  def public! do
    (%Client{} = client) = tuist_oauth_client()
    client
  end

  @impl Clients
  def authorized_scopes(%Client{id: client_id} = client) do
    case static_client(client_id) do
      %Client{} = static ->
        if static.id == luft_server_client_id(),
          do: Enum.map(@luft_server_scopes, &%Scope{name: &1}),
          else: []

      nil ->
        EctoClients.authorized_scopes(client)
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
    |> Map.put(:pkce, true)
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

  @doc """
  The public keys ID tokens are signed with, as a JWK Set (RFC 7517), for the
  provider's `jwks_uri`. Only the OpenID Connect signing key: Boruta's
  `list_clients_jwk/0` also returns the keys clients authenticate with.
  """
  def oidc_jwks do
    keys =
      case luft_server_client() do
        %Client{} ->
          # Every configured key, not only the one that signs, so a key is
          # published before it signs and stays published while tokens signed
          # with it are live. See `Environment.oidc_signing_keys/1`.
          for private_key <- Environment.oidc_signing_keys() do
            {_fields, public} = private_key |> JOSE.JWK.from_pem() |> JOSE.JWK.to_public_map()
            # The same `kid` Boruta puts in the ID token's header.
            kid = Crypto.kid_from_private_key(private_key)
            Map.merge(public, %{"kid" => kid, "use" => "sig", "alg" => "RS256"})
          end

        nil ->
          []
      end

    %{"keys" => keys}
  end

  @impl Boruta.Openid.Clients
  # Boruta refreshes a key by fetching the client's `jwks_uri` with an
  # unguarded HTTP GET whenever a client assertion fails to verify, so a stored
  # URI would let anyone holding a client ID make the server request it.
  def refresh_jwk_from_jwks_uri(_client_id), do: {:error, "JWK refresh from JWKS URI not supported"}

  defp static_client(client_id) when is_binary(client_id) do
    Enum.find(
      [kura_introspection_client(), tuist_oauth_client(), luft_client(), luft_server_client()],
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
        http_config = Application.get_env(:tuist, Tuist.Web.endpoint())[:http] || []
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

  defp luft_client do
    %Client{
      id: @luft_client_id,
      name: "Luft",
      access_token_ttl: 86_400,
      authorization_code_ttl: @authorization_code_ttl,
      refresh_token_ttl: 2_592_000,
      # The mobile apps' scheme, and the desktop app's loopback callback on any port (RFC 8252 7.3).
      redirect_uris: ["luft://oauth-callback", "http://127.0.0.1:*/callback"],
      # Luft requests no scope; `TuistWeb.Oauth.AuthorizeController` refuses
      # any, since Boruta would otherwise allow public scopes and `openid`,
      # and this client has no keys to sign ID tokens with.
      authorize_scope: false,
      supported_grant_types: @supported_grant_types,
      pkce: true,
      public_refresh_token: true,
      public_revoke: true,
      confidential: false,
      token_endpoint_auth_methods: ["none"],
      enforce_dpop: false
    }
  end

  defp luft_server_client do
    with id when is_binary(id) <- Environment.luft_server_oauth_client_id(),
         secret when is_binary(secret) <- Environment.luft_server_oauth_client_secret(),
         [_ | _] = redirect_uris <- Environment.luft_server_oauth_redirect_uris(),
         private_key when is_binary(private_key) <- Environment.oidc_signing_key() do
      %Client{
        id: id,
        secret: secret,
        name: "Luft",
        access_token_ttl: 3_600,
        authorization_code_ttl: @authorization_code_ttl,
        refresh_token_ttl: 2_592_000,
        id_token_ttl: 3_600,
        id_token_signature_alg: "RS256",
        # Exact HTTPS callbacks (OAuth 2.0 Security BCP, RFC 9700 4.1).
        redirect_uris: redirect_uris,
        # Only the scopes `authorized_scopes/1` lists: `luft_server_scopes/0`.
        authorize_scope: true,
        supported_grant_types: @supported_grant_types,
        # Confidential, and PKCE all the same (RFC 9700 2.1.1).
        pkce: true,
        public_refresh_token: false,
        public_revoke: false,
        confidential: true,
        token_endpoint_auth_methods: ["client_secret_basic", "client_secret_post"],
        private_key: private_key,
        # Ecto clients get this default from their schema; static ones must name it.
        signatures_adapter: "Elixir.Boruta.Internal.Signatures",
        enforce_dpop: false
      }
    else
      _ -> nil
    end
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
    Map.put(jwk, "kid", Crypto.kid_from_private_key(private_key))
  end

  defp to_client_jwk(_), do: nil

  defp ensure_authorization_code_ttl(%Client{authorization_code_ttl: ttl} = client) when ttl < @authorization_code_ttl do
    %{client | authorization_code_ttl: @authorization_code_ttl}
  end

  defp ensure_authorization_code_ttl(%Client{} = client), do: client

  # Clients registered before redirect URIs were restricted keep only those
  # that are still allowed. Every dynamically registered client is public in
  # practice and must use PKCE (RFC 9700 section 2.1.1), set above.
  defp restrict_redirect_uris(%Client{redirect_uris: redirect_uris} = client) do
    %{client | redirect_uris: Enum.filter(redirect_uris || [], &allowed_redirect_uri?/1)}
  end

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
