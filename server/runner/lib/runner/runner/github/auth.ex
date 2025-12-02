defmodule Runner.Runner.GitHub.Auth do
  @moduledoc """
  Handles JWT generation and OAuth token management for GitHub Actions runner protocol.

  The GitHub Actions runner uses RSA-signed JWTs to authenticate with the Broker API
  and obtain OAuth access tokens for subsequent API calls.
  """

  require Logger

  @jwt_expiry_seconds 300
  @token_refresh_buffer_seconds 60

  @type credentials :: %{
          rsa_private_key: String.t(),
          auth_url: String.t(),
          access_token: String.t() | nil,
          token_expires_at: DateTime.t() | nil
        }

  @doc """
  Generates a JWT signed with the RSA private key.

  The JWT is used to authenticate with GitHub's authorization endpoint
  to obtain an OAuth access token.
  """
  @spec generate_jwt(String.t() | map(), String.t(), String.t() | nil, String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def generate_jwt(rsa_private_key, _runner_id, client_id, auth_url \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    # GitHub Actions runner JWT claims:
    # sub: the client_id (UUID) from credentials
    # iss: same as sub
    # aud: derived from the auth URL (the base URL without /token)
    # jti: unique token ID (random UUID)
    # nbf: not before (must be present)
    audience = extract_audience_from_url(auth_url)

    claims = %{
      "sub" => client_id,
      "iss" => client_id,
      "aud" => audience,
      "iat" => now,
      "nbf" => now,
      "exp" => now + @jwt_expiry_seconds,
      "jti" => UUID.uuid4()
    }

    try do
      jwk = load_jwk(rsa_private_key)
      jws = %{"alg" => "RS256"}

      {_, jwt} = JOSE.JWT.sign(jwk, jws, claims) |> JOSE.JWS.compact()

      {:ok, jwt}
    rescue
      e -> {:error, e}
    end
  end

  # Extract audience from auth URL
  # e.g., "https://pipelinesghubeus21.actions.githubusercontent.com/ABC123/_apis/oauth2/token"
  # -> "https://pipelinesghubeus21.actions.githubusercontent.com/ABC123"
  defp extract_audience_from_url(nil), do: "pipelines"

  defp extract_audience_from_url(url) when is_binary(url) do
    # The audience is the full authorization URL
    url
  end

  # Load JWK from different formats
  defp load_jwk(key) when is_map(key) do
    # Already in JWK format (from GitHub's RSA params)
    JOSE.JWK.from_map(key)
  end

  defp load_jwk(key) when is_binary(key) do
    if String.contains?(key, "PRIVATE KEY") do
      # PEM format
      JOSE.JWK.from_pem(key)
    else
      # Try as JWK JSON
      case Jason.decode(key) do
        {:ok, map} -> JOSE.JWK.from_map(map)
        _ -> JOSE.JWK.from_pem(key)
      end
    end
  end

  @doc """
  Exchanges a JWT for an OAuth access token.

  Posts to the authorization URL with the JWT to obtain a bearer token
  that can be used for subsequent API calls.
  """
  @spec get_access_token(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_access_token(auth_url, jwt) do
    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"}
    ]

    # GitHub's OAuth endpoint expects form-urlencoded body with client_credentials grant
    body = URI.encode_query(%{
      "grant_type" => "client_credentials",
      "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion" => jwt
    })

    case Req.post(auth_url, headers: headers, body: body, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_token_response(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Failed to get access token: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to get access token: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Ensures credentials have a valid access token, refreshing if needed.

  Returns updated credentials with a fresh token if the current one
  is expired or about to expire.
  """
  @spec ensure_valid_token(credentials()) :: {:ok, credentials()} | {:error, term()}
  def ensure_valid_token(credentials) do
    if token_valid?(credentials) do
      {:ok, credentials}
    else
      refresh_token(credentials)
    end
  end

  @doc """
  Refreshes the access token using the RSA private key.
  """
  @spec refresh_token(credentials()) :: {:ok, credentials()} | {:error, term()}
  def refresh_token(credentials) do
    client_id = Map.get(credentials, :client_id)
    auth_url = Map.get(credentials, :auth_url)

    with {:ok, jwt} <- generate_jwt(credentials.rsa_private_key, credentials.runner_id, client_id, auth_url),
         {:ok, token_info} <- get_access_token(credentials.auth_url, jwt) do
      updated_credentials = %{
        credentials
        | access_token: token_info.access_token,
          token_expires_at: token_info.expires_at
      }

      {:ok, updated_credentials}
    end
  end

  @doc """
  Creates authorization headers for API requests.
  """
  @spec auth_headers(credentials()) :: [{String.t(), String.t()}]
  def auth_headers(credentials) do
    [{"Authorization", "Bearer #{credentials.access_token}"}]
  end

  # Private functions

  defp parse_token_response(body) when is_map(body) do
    expires_at =
      if body["expires_in"] do
        DateTime.utc_now() |> DateTime.add(body["expires_in"], :second)
      else
        nil
      end

    %{
      access_token: body["access_token"] || body["token"],
      expires_at: expires_at
    }
  end

  defp parse_token_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_token_response(decoded)
      {:error, _} -> %{access_token: nil, expires_at: nil}
    end
  end

  defp token_valid?(%{access_token: nil}), do: false
  defp token_valid?(%{token_expires_at: nil}), do: false

  defp token_valid?(%{token_expires_at: expires_at}) do
    buffer = DateTime.utc_now() |> DateTime.add(@token_refresh_buffer_seconds, :second)
    DateTime.compare(expires_at, buffer) == :gt
  end
end
