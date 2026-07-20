defmodule Tuist.OAuth.Apple do
  @moduledoc """
  Apple OAuth client secret generation and authentication for Sign in with Apple.
  """

  alias Tuist.Accounts

  require Logger

  @apple_issuer "https://appleid.apple.com"
  @apple_public_keys_url "https://appleid.apple.com/auth/keys"
  # Apple signs identity tokens with RS256. Pinning the accepted algorithms
  # prevents algorithm-substitution attacks (e.g. an attacker downgrading to
  # "none" or an HMAC forged with a public key).
  @allowed_algorithms ["RS256"]
  # Tolerance, in seconds, applied to the `exp` claim to absorb minor clock skew.
  @clock_skew_seconds 60

  @doc """
  Generates the client secret for Apple OAuth using the private key.
  The client secret is a JWT token that expires in 6 months but cached for 5 months.
  Uses Redis for persistent caching across deployments.
  """
  def client_secret(config \\ []) do
    client_id = Keyword.get(config, :client_id, Tuist.Environment.apple_service_client_id())
    cache_key = [__MODULE__, "client_secret", client_id]

    cache_opts = [
      # 5 months
      ttl: to_timeout(day: 30 * 5),
      persist_across_deployments: true
    ]

    Tuist.KeyValueStore.get_or_update(cache_key, cache_opts, fn ->
      generate_client_secret(client_id)
    end)
  end

  defp generate_client_secret(client_id) do
    UeberauthApple.generate_client_secret(%{
      client_id: client_id,
      # 6 months
      expires_in: 86_400 * 180,
      key_id: Tuist.Environment.apple_private_key_id(),
      team_id: Tuist.Environment.apple_team_id(),
      private_key: Tuist.Environment.apple_private_key()
    })
  end

  @doc """
  Verifies the Apple identity token and creates or finds the matching user.

  The identity token is validated end to end before any claim is trusted: its
  signature is verified against Apple's published public keys, and the `iss`,
  `aud`, and `exp` claims are asserted. Skipping these checks would let a forged
  or replayed token impersonate any account (the class of flaw behind
  CVE-2026-55954), which `JOSE.JWT.peek_payload/1` alone does not guard against.
  """
  def verify_apple_identity_token_and_create_user(identity_token, authorization_code) do
    with :ok <- validate_apple_authorization_code(authorization_code),
         {:ok, claims} <- verify_identity_token(identity_token) do
      sub = claims["sub"]
      email = claims["email"]

      auth = %Ueberauth.Auth{
        provider: :apple,
        uid: sub,
        info: %Ueberauth.Auth.Info{
          email: email
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            user: %{
              "sub" => sub,
              "email" => email
            },
            token: %{
              "identity_token" => identity_token,
              "authorization_code" => authorization_code
            }
          }
        }
      }

      user = Accounts.find_or_create_user_from_oauth2(auth, preload: [:account])
      {:ok, user}
    end
  end

  defp verify_identity_token(identity_token) do
    with {:ok, key_id} <- token_key_id(identity_token),
         {:ok, jwk} <- apple_public_key(key_id),
         {:ok, claims} <- verify_signature(jwk, identity_token),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    else
      {:error, reason} = error ->
        Logger.warning("[Apple] Rejected Sign in with Apple identity token: #{reason}")
        error
    end
  end

  defp token_key_id(identity_token) do
    case JOSE.JWT.peek_protected(identity_token) do
      %JOSE.JWS{fields: %{"kid" => key_id}} -> {:ok, key_id}
      _ -> {:error, :missing_key_id}
    end
  rescue
    _ -> {:error, :malformed_token}
  end

  defp apple_public_key(key_id) do
    with {:ok, keys} <- fetch_apple_public_keys(),
         %{} = key <- Enum.find(keys, fn key -> key["kid"] == key_id end) do
      {:ok, JOSE.JWK.from_map(key)}
    else
      nil -> {:error, :unknown_signing_key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_apple_public_keys do
    case Req.get(@apple_public_keys_url) do
      {:ok, %{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        {:ok, keys}

      {:ok, %{status: _status}} ->
        {:error, :public_keys_unavailable}

      {:error, _exception} ->
        {:error, :public_keys_request_failed}
    end
  end

  defp verify_signature(jwk, identity_token) do
    case JOSE.JWT.verify_strict(jwk, @allowed_algorithms, identity_token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_claims(claims) do
    expected_audience = Tuist.Environment.apple_app_client_id()
    now = DateTime.to_unix(DateTime.utc_now())

    cond do
      is_nil(expected_audience) ->
        {:error, :missing_audience_configuration}

      claims["iss"] != @apple_issuer ->
        {:error, :invalid_issuer}

      not audience_matches?(claims["aud"], expected_audience) ->
        {:error, :invalid_audience}

      not is_integer(claims["exp"]) or claims["exp"] + @clock_skew_seconds < now ->
        {:error, :token_expired}

      is_nil(claims["sub"]) or claims["sub"] == "" ->
        {:error, :missing_subject}

      true ->
        :ok
    end
  end

  defp audience_matches?(audience, expected) when is_binary(audience), do: audience == expected
  defp audience_matches?(audience, expected) when is_list(audience), do: expected in audience
  defp audience_matches?(_audience, _expected), do: false

  defp validate_apple_authorization_code(authorization_code) do
    body = %{
      client_id: Tuist.Environment.apple_app_client_id(),
      client_secret: client_secret(client_id: Tuist.Environment.apple_app_client_id()),
      code: authorization_code,
      grant_type: "authorization_code"
    }

    case Req.post("https://appleid.apple.com/auth/token",
           form: body,
           headers: [{"content-type", "application/x-www-form-urlencoded"}]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: _body}} ->
        {:error, "Apple authorization code validation failed with #{status} error code."}

      {:error, _exception} ->
        {:error, "The request to Apple to validate the token has failed."}
    end
  end
end
