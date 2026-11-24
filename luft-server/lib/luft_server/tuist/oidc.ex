defmodule LuftServer.Tuist.OIDC do
  @moduledoc """
  Luft's side of signing in with Tuist: an OpenID Connect relying party
  (OpenID Connect Core 1.0) using the authorization code flow as a
  confidential client, with PKCE (RFC 7636) and a nonce.

  The provider is discovered from `<issuer>/.well-known/openid-configuration`
  (OpenID Connect Discovery 1.0), so nothing but the issuer is configured.
  Metadata and signing keys are kept per node for `@metadata_ttl`; they are a
  disposable cache, and an ID token signed with a key the cache does not know
  refetches the keys once (key rotation).
  """

  alias LuftServer.Config

  # Explicit confidential-client grants; this is not Tuist's first-party native client.
  @scope "openid profile email account:organizations:write luft:app mcp account:delete account:members:read account:sandboxes:write account:repositories:read account:repositories:write project:admin:read project:previews:read project:previews:write"
  @metadata_ttl to_timeout(minute: 15)
  @clock_skew 60

  @doc "A fresh state, nonce and PKCE verifier for one sign-in."
  def new_transaction do
    %{"state" => random(), "nonce" => random(), "verifier" => random()}
  end

  @doc """
  The provider's authorization URL for `transaction`. `prompt: "create"` asks
  the provider to have the person sign up (Initiating User Registration via
  OpenID Connect 1.0).
  """
  def authorization_url(%{"state" => state, "nonce" => nonce, "verifier" => verifier}, opts \\ []) do
    with {:ok, metadata} <- metadata() do
      params =
        Enum.reject(
          [
            response_type: "code",
            client_id: Config.oauth_client_id(),
            redirect_uri: Config.redirect_uri(),
            scope: @scope,
            state: state,
            nonce: nonce,
            code_challenge:
              :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false),
            code_challenge_method: "S256",
            prompt: opts[:prompt]
          ],
          fn {_key, value} -> is_nil(value) end
        )

      endpoint =
        case opts[:provider] do
          provider when provider in ["apple", "google", "github"] ->
            uri = URI.parse(metadata["authorization_endpoint"])
            URI.to_string(%{uri | path: Path.join(Path.dirname(uri.path), provider)})

          _ ->
            metadata["authorization_endpoint"]
        end

      {:ok, endpoint <> "?" <> URI.encode_query(params)}
    end
  end

  @doc """
  Exchanges an authorization code and verifies the ID token it comes with.
  Returns `{:ok, %{claims: claims, tokens: tokens}}`.
  """
  def exchange_code(code, %{"nonce" => nonce, "verifier" => verifier}) do
    with {:ok, tokens} <-
           token_request(
             grant_type: "authorization_code",
             code: code,
             redirect_uri: Config.redirect_uri(),
             code_verifier: verifier
           ),
         {:ok, claims} <- verify_id_token(tokens["id_token"], nonce) do
      {:ok, %{claims: claims, tokens: tokens}}
    end
  end

  @doc "Refreshes the access token (RFC 6749, section 6). The refresh token rotates."
  def refresh(refresh_token) do
    token_request(grant_type: "refresh_token", refresh_token: refresh_token)
  end

  @doc "Revokes a refresh token (RFC 7009) on sign-out. Best effort."
  def revoke(refresh_token) do
    with {:ok, %{"revocation_endpoint" => endpoint}} <- metadata() do
      Req.post(
        endpoint,
        client_request_options(form: [token: refresh_token, token_type_hint: "refresh_token"])
      )
    end

    :ok
  end

  @doc """
  Verifies an ID token as OpenID Connect Core 1.0, section 3.1.3.7 requires:
  an RS256 signature by one of the provider's keys, `iss` equal to the
  configured issuer, `aud` containing this client, `exp` in the future, and
  the `nonce` this sign-in sent.
  """
  def verify_id_token(id_token, nonce) when is_binary(id_token) do
    with {:ok, kid} <- kid(id_token),
         {:ok, jwk} <- signing_key(kid),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(jwk, ["RS256"], id_token),
         :ok <- check_claims(claims, nonce) do
      {:ok, claims}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_id_token}
    end
  end

  def verify_id_token(_id_token, _nonce), do: {:error, :invalid_id_token}

  defp check_claims(claims, nonce) do
    now = System.system_time(:second)
    client_id = Config.oauth_client_id()

    cond do
      claims["iss"] != Config.tuist_issuer() -> {:error, :invalid_issuer}
      client_id not in List.wrap(claims["aud"]) -> {:error, :invalid_audience}
      not is_integer(claims["exp"]) or claims["exp"] + @clock_skew < now -> {:error, :expired}
      not is_binary(nonce) or claims["nonce"] != nonce -> {:error, :invalid_nonce}
      not is_binary(claims["sub"]) -> {:error, :invalid_id_token}
      true -> :ok
    end
  end

  defp kid(id_token) do
    case JOSE.JWT.peek_protected(id_token) do
      %JOSE.JWS{alg: {_, :RS256}, fields: %{"kid" => kid}} -> {:ok, kid}
      _ -> {:error, :invalid_id_token}
    end
  rescue
    _ -> {:error, :invalid_id_token}
  end

  defp signing_key(kid) do
    with {:ok, keys} <- cached(:jwks, &fetch_jwks/0) do
      case find_key(keys, kid) do
        nil -> refetched_signing_key(kid)
        key -> {:ok, JOSE.JWK.from_map(key)}
      end
    end
  end

  # The provider may have rotated its key since the keys were cached.
  defp refetched_signing_key(kid) do
    :persistent_term.erase({__MODULE__, :jwks})

    with {:ok, keys} <- cached(:jwks, &fetch_jwks/0),
         %{} = key <- find_key(keys, kid) do
      {:ok, JOSE.JWK.from_map(key)}
    else
      _ -> {:error, :unknown_signing_key}
    end
  end

  defp find_key(keys, kid), do: Enum.find(keys, &(&1["kid"] == kid))

  defp fetch_jwks do
    with {:ok, %{"jwks_uri" => jwks_uri}} <- metadata(),
         {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) <-
           Req.get(jwks_uri, request_options()) do
      {:ok, keys}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

  def metadata do
    cached(:metadata, fn ->
      issuer = Config.tuist_issuer()

      case Req.get(issuer <> "/.well-known/openid-configuration", request_options()) do
        # The metadata must name the issuer it was fetched for (Discovery 1.0, 4.3).
        {:ok, %Req.Response{status: 200, body: %{"issuer" => ^issuer} = metadata}} ->
          {:ok, metadata}

        _ ->
          {:error, :provider_unavailable}
      end
    end)
  end

  defp token_request(form) do
    with {:ok, %{"token_endpoint" => endpoint}} <- metadata() do
      case Req.post(endpoint, client_request_options(form: form)) do
        {:ok, %Req.Response{status: 200, body: %{"access_token" => _} = tokens}} ->
          {:ok, tokens}

        # Tuist answers a deleted user's refresh with a 200 and no token;
        # the grant is as dead as an `invalid_grant`.
        {:ok, %Req.Response{status: 200, body: %{}}} ->
          {:error, {:oauth, "invalid_grant"}}

        {:ok, %Req.Response{status: status, body: %{"error" => error}}} when status in 400..401 ->
          {:error, {:oauth, error}}

        _ ->
          {:error, :provider_unavailable}
      end
    end
  end

  # The client authenticates with HTTP Basic (RFC 6749, section 2.3.1).
  defp client_request_options(options) do
    request_options(
      [auth: {:basic, "#{Config.oauth_client_id()}:#{Config.oauth_client_secret()}"}] ++ options
    )
  end

  defp request_options(options \\ []) do
    [receive_timeout: 10_000] |> Keyword.merge(Config.req_options()) |> Keyword.merge(options)
  end

  defp cached(key, fun) do
    if Config.cache_provider_metadata?(), do: persistent_cached(key, fun), else: fun.()
  end

  defp persistent_cached(key, fun) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {value, expires_at} when expires_at > now ->
        {:ok, value}

      _ ->
        with {:ok, value} <- fun.() do
          :persistent_term.put({__MODULE__, key}, {value, now + @metadata_ttl})
          {:ok, value}
        end
    end
  end

  defp random, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
