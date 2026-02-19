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

  # Dev-only defaults used when secrets are not configured (no dev.key).
  # These match the client_id in app/Project.swift and android/app/build.gradle.kts.
  @dev_client_id "5339abf2-467c-4690-b816-17246ed149d2"
  @dev_client_secret "dev-secret"
  @dev_client_name "Tuist Dev"
  @dev_private_key """
  -----BEGIN PRIVATE KEY-----
  MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCfE46V1FBIR+IN
  oCVsQ/oTBx1cZzB7O+be1jaUEFPa4R0hNZG1yYcD0TA3nugMmy7bDzF5d1prOYff
  gnTgO+BaM4jW/yT8IVNZnDj8yh5SPMr0DtMj4Onf5g+8dIeyyXrVbxCUul09vjmz
  k9GGQpivFIFAoXtApESI92ONaSQtJpxhWMU0yxVH7g6YwqUDz7FWYhG5rSZHhycH
  dY6xL5Md0dcdFakrScZpL+1WRvQiYjfJEjmDUUtH0kByH39BEb1+VldDi5B/peV7
  OC5RMxGkGxdqi0ZiDwjh/s7J8ks3/BrNTpmn76ivMNexcaVTxs9CH1ZRdpVN3/E6
  AOblQGS9AgMBAAECggEABZUGWyAe7BZnqpI81fKBt0K350rwstZciOPL+QCkrKjb
  IJP0Z8RpYjsoPb9sBas5ZvL+ybQkPmB/sdpuVwMK4aduzRqZdeaGef3HKym9jCW5
  enx9sMPe+R4l3bdaHq4+yvgRhSKQDI9dD33nq5YxLO2jhnzUKiXJiOPjgK4YmKP0
  wPo/xiI5nBln20chZ5CruM7vxRtLHDL/OfKCeCWYYjCQhOn3OlByG1fnj/LXg4XY
  iDuwOuh6hCy93CVffQ1/ODb+vSh2gK0ovWao7CSzxhZ58Y57dqDMBPy5GdYOTf+n
  HJZD+esO+Trv0JLPm7k4krUCEXDFJ7aETbEAHCMyCQKBgQDbZc3sqVg1QqkvFyRQ
  o+T/MMOidJNftAbtEzJjLAFtXe/G71TqFTFegTBXgwrA5ZRBQ237pgFkJ7khbBCT
  zCTSsa4gx/4gfg/OurHnmrSsLRpikzjZS91RM8CDtPdTsk5V0LQ5vc9MK9J5PW0r
  z2k77r+56e/gELIbWgUiCt4uJQKBgQC5nYHpnfSIGaNiul0MzeOYaEegfqwMmFTL
  HfOzB9SsaSU/S7n++oZzc3LkSrA5Ub9m+H7fCjufsuVTzNfxOcMryOBSS3D6cMX9
  +jm1zP5dI7XQlUOQKrsfCL6TYBn7DOe5qVL8Z6//3aDgIr4TGiILOLRDqb/p+h6c
  cLd4eYEcuQKBgEzW7fVKJiuZKjnk6AIaNLSvtoTqQUdOfPKBO6+CFQnh0X2iCuJl
  A8JuiqjLq3N9tJva6uUs8eXLB8rN10x8PhVQx4SRps5oeE7WEkLkawy2SzxlBY8N
  Q/kRoAZA1jKJC2iAzO5ALR8nZfKycc7bOKcV6i5J4YpfLpHnyE5w8fnFAoGBALdV
  Hkr8C9od0KYkQuHxvjn7zbt1QkRSdXYFyH3tXx9H31VMW5LAKeqAfluEddi3qKBx
  EwcD2W5cSWxi6GtHzUFC8GX4Q8fpeXXpH/U0W4ztR5iUxZ3wxs/ZWDrCcgbocTyN
  RP0vAMRtSIf5aNn/Nt70jABE+tyEgpWsM1tYT7FpAoGAJodQyxogsFXVPW1HvksR
  Br4wt33bclVitwXqr3DM2iqMMvhR/G5BL2qKyR1kbUbQzxgyae504OSuY+IEq4L/
  /EX2YVX2ZjkzrCxfeLWow9cVQNG3+ILxrzIBzI4MXfIj2n1GFlXP4jCdWuFPuzD6
  8Jl6Fy9vOBXqtizQf8u/CjE=
  -----END PRIVATE KEY-----
  """
  @dev_public_key """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnxOOldRQSEfiDaAlbEP6
  EwcdXGcwezvm3tY2lBBT2uEdITWRtcmHA9EwN57oDJsu2w8xeXdaazmH34J04Dvg
  WjOI1v8k/CFTWZw4/MoeUjzK9A7TI+Dp3+YPvHSHssl61W8QlLpdPb45s5PRhkKY
  rxSBQKF7QKREiPdjjWkkLSacYVjFNMsVR+4OmMKlA8+xVmIRua0mR4cnB3WOsS+T
  HdHXHRWpK0nGaS/tVkb0ImI3yRI5g1FLR9JAch9/QRG9flZXQ4uQf6XlezguUTMR
  pBsXaotGYg8I4f7OyfJLN/wazU6Zp++orzDXsXGlU8bPQh9WUXaVTd/xOgDm5UBk
  vQIDAQAB
  -----END PUBLIC KEY-----
  """

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
    %Boruta.Oauth.Client{
      id: Environment.oauth_client_id() || dev_default(:client_id),
      secret: Environment.oauth_client_secret() || dev_default(:client_secret),
      name: Environment.oauth_client_name() || dev_default(:client_name),
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
      jwt_public_key: Environment.oauth_jwt_public_key() || dev_default(:public_key),
      private_key: Environment.oauth_private_key() || dev_default(:private_key),
      enforce_dpop: false
    }
  end

  if Mix.env() == :dev do
    defp dev_default(:client_id), do: @dev_client_id
    defp dev_default(:client_secret), do: @dev_client_secret
    defp dev_default(:client_name), do: @dev_client_name
    defp dev_default(:private_key), do: String.trim(@dev_private_key)
    defp dev_default(:public_key), do: String.trim(@dev_public_key)
  else
    defp dev_default(_), do: nil
  end
end
