defmodule Tuist.Entire.Client do
  @moduledoc """
  Entire's partner plugin protocol: signed installations and deliveries,
  repository discovery, and repository-scoped API access.
  """

  alias Tuist.KeyValueStore

  @cores for region <- ~w(us eu au in uk sg), suffix <- ~w(io com), do: "https://#{region}.auth.entire.#{suffix}"

  def config, do: Application.get_env(:tuist, __MODULE__, [])

  def configured? do
    Enum.all?(
      [:slug, :private_key, :delivery_jwks_url],
      &(is_binary(__MODULE__.config()[&1]) and __MODULE__.config()[&1] != "")
    )
  end

  def install_url(callback, state) do
    "https://entire.com/plugins/#{__MODULE__.config()[:slug]}/install?" <>
      URI.encode_query(%{redirect_uri: callback, state: state})
  end

  def verify_receipt(token, state) do
    with {:ok, header, claims} <- peek(token),
         true <- claims["iss"] in @cores,
         true <- header["typ"] == "entire-install-receipt+jwt",
         {:ok, claims} <- verify(token, header, claims["iss"] <> "/.well-known/jwks.json"),
         true <- audience?(claims, "urn:entire:plugin:" <> __MODULE__.config()[:slug]),
         true <- claims["plugin_id"] == __MODULE__.config()[:slug],
         true <- secure_equal?(claims["state"], state),
         true <- nonempty?(claims["installation_id"]) and nonempty?(claims["jti"]),
         true <- is_nil(claims["sub"]) or claims["sub"] == claims["installation_id"] do
      {:ok, claims}
    else
      {:error, :unavailable} = error -> error
      _ -> {:error, :invalid_receipt}
    end
  end

  def verify_delivery(token, body) do
    with {:ok, header, _claims} <- peek(token),
         {:ok, claims} <- verify(token, header, __MODULE__.config()[:delivery_jwks_url]),
         true <- trusted_origin?(claims["iss"]),
         true <- audience?(claims, __MODULE__.config()[:slug]),
         true <- nonempty?(claims["jti"]),
         digest = Base.url_encode64(:crypto.hash(:sha256, body), padding: false),
         true <- secure_equal?(claims["body_sha256"], digest),
         {:ok, delivery} when is_map(delivery) <- JSON.decode(body),
         true <- delivery["plugin_id"] == __MODULE__.config()[:slug],
         true <- Enum.all?(~w(delivery_id installation_id), &nonempty?(delivery[&1])) do
      {:ok, delivery, claims["jti"]}
    else
      {:error, :unavailable} = error -> error
      _ -> {:error, :invalid_delivery}
    end
  end

  def repositories(installation), do: repository_page(installation, nil, [])

  defp repository_page(installation, cursor, repositories) do
    opts = if cursor, do: [params: [cursor: cursor]], else: []

    with {:ok, body} <- core_request(:get, installation, "/repositories", opts) do
      repositories = repositories ++ (body["repositories"] || [])

      case body["next_cursor"] do
        cursor when is_binary(cursor) and cursor != "" -> repository_page(installation, cursor, repositories)
        _ -> {:ok, repositories}
      end
    end
  end

  def repository(installation, repository_id) do
    with {:ok, repositories} <- repositories(installation),
         repository when not is_nil(repository) <- Enum.find(repositories, &(&1["id"] == repository_id)),
         placement when not is_nil(placement) <-
           Enum.find(repository["placements"] || [], &(&1["role"] == "processing_primary")),
         true <- trusted_origin?(placement["api_base_url"]),
         true <- trusted_clone_url?(repository["entire_clone_url"]) do
      {:ok,
       %{
         id: repository_id,
         name: repository["full_name"],
         api_url: placement["api_base_url"],
         clone_url: repository["entire_clone_url"]
       }}
    else
      nil -> {:error, :revoked}
      false -> {:error, :invalid_repository}
      {:error, _} = error -> error
    end
  end

  def access_token(installation, repository_id, permissions) do
    scope_key = :sha256 |> :crypto.hash(:erlang.term_to_binary(permissions)) |> Base.encode16(case: :lower)
    key = [__MODULE__, :token, installation.remote_id, repository_id, scope_key]

    cached(key, fn ->
      case core_request(:post, installation, "/access-tokens",
             json: %{repository_id: repository_id, permissions: permissions}
           ) do
        {:ok, %{"token" => token}} -> {:ok, token}
        {:error, _} = error -> error
      end
    end)
  end

  defp core_request(method, installation, suffix, opts) do
    core = __MODULE__.config()[:core_url] || "https://eu.auth.entire.io"

    with true <- core in @cores,
         {:ok, jwt} <- plugin_jwt(core, installation.remote_id) do
      request(
        method,
        core <>
          "/api/v1/plugins/#{segment(__MODULE__.config()[:slug])}/installations/#{segment(installation.remote_id)}" <>
          suffix,
        jwt,
        opts
      )
    else
      _ -> {:error, :not_configured}
    end
  end

  def region_request(method, repository, path, token, opts \\ []) do
    if trusted_origin?(repository.api_url) do
      request(method, repository.api_url <> "/api/v1" <> path, token, opts)
    else
      {:error, :invalid_repository}
    end
  end

  defp plugin_jwt(core, installation_id) do
    now = System.system_time(:second) - 30

    claims = %{
      "iss" => "urn:entire:plugin:" <> __MODULE__.config()[:slug],
      "aud" => core <> "/api/authz/sts",
      "plugin_id" => __MODULE__.config()[:slug],
      "installation_id" => installation_id,
      "iat" => now,
      "exp" => now + 300
    }

    header =
      if __MODULE__.config()[:key_id],
        do: %{"alg" => "EdDSA", "kid" => __MODULE__.config()[:key_id]},
        else: %{"alg" => "EdDSA"}

    {_, token} =
      __MODULE__.config()[:private_key] |> JOSE.JWK.from_pem() |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()

    {:ok, token}
  end

  defp request(method, url, token, opts) do
    opts =
      [
        method: method,
        url: url,
        headers: [{"authorization", "Bearer " <> token}],
        redirect: false,
        retry: false,
        receive_timeout: 5_000
      ] ++ opts

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 404, body: %{"type" => type}}} when is_binary(type) ->
        cond do
          String.ends_with?(type, "/git-read/path-not-found") -> {:error, {:path_not_found, type}}
          String.contains?(type, "/git-read/") -> {:error, :source_unavailable}
          true -> {:error, :revoked}
        end

      {:ok, %{status: status}} when status in [403, 404] ->
        {:error, :revoked}

      {:ok, %{status: status}} ->
        {:error, {:entire_http, status}}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  defp peek(token) when is_binary(token) and byte_size(token) <= 16_384 do
    {_, header} = token |> JOSE.JWT.peek_protected() |> JOSE.JWS.to_map()
    {:ok, header, JOSE.JWT.peek_payload(token).fields}
  rescue
    _ -> {:error, :invalid_jwt}
  end

  defp peek(_), do: {:error, :invalid_jwt}

  defp verify(token, header, jwks_url) do
    with true <- header["alg"] == "EdDSA" and nonempty?(header["kid"]),
         {:ok, key} <- signing_key(jwks_url, header["kid"]),
         {true, jwt, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["EdDSA"], token),
         true <- valid_times?(jwt.fields) do
      {:ok, jwt.fields}
    else
      {:error, :unavailable} = error -> error
      _ -> {:error, :invalid_jwt}
    end
  rescue
    _ -> {:error, :invalid_jwt}
  end

  defp signing_key(url, kid) do
    with {:ok, keys} <- jwks(url) do
      case Enum.find(keys, &(&1["kid"] == kid and &1["kty"] == "OKP" and &1["crv"] == "Ed25519")) do
        nil ->
          with {:ok, keys} <- jwks(url, true),
               key when not is_nil(key) <-
                 Enum.find(keys, &(&1["kid"] == kid and &1["kty"] == "OKP" and &1["crv"] == "Ed25519")) do
            {:ok, key}
          else
            # A rotated key may be waiting for the refresh cooldown.
            nil -> {:error, :unavailable}
            error -> error
          end

        key ->
          {:ok, key}
      end
    end
  end

  defp jwks(url, refresh \\ false) do
    if trusted_jwks_url?(url) do
      cached(
        [__MODULE__, :jwks, url],
        fn -> refresh_jwks(url) end,
        refresh
      )
    else
      {:error, :invalid_jwt}
    end
  end

  defp refresh_jwks(url) do
    KeyValueStore.get_or_update(
      [__MODULE__, :jwks_refresh, url],
      [cache: :entire_jwks, ttl: to_timeout(second: 30)],
      fn ->
        case Req.get(url: url, redirect: false, retry: false, receive_timeout: 3_000) do
          {:ok, %{status: 200, body: %{"keys" => keys}}} when is_list(keys) -> {:ok, keys}
          _ -> {:error, :unavailable}
        end
      end
    )
  end

  defp valid_times?(%{"iat" => issued, "exp" => expires}) when is_integer(issued) and is_integer(expires) do
    now = System.system_time(:second)
    issued <= now + 60 and expires > now and expires > issued and expires - issued <= 600
  end

  defp valid_times?(_), do: false
  defp audience?(claims, audience), do: audience in List.wrap(claims["aud"])
  defp nonempty?(value), do: is_binary(value) and value != ""
  defp secure_equal?(a, b) when is_binary(a) and is_binary(b), do: a != "" and Plug.Crypto.secure_compare(a, b)
  defp secure_equal?(_, _), do: false
  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp trusted_origin?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil, path: path, port: 443}
      when path in [nil, ""] ->
        trusted_host?(host)

      _ ->
        false
    end
  end

  defp trusted_origin?(_), do: false

  defp trusted_host?(host) when is_binary(host),
    do: Enum.any?(~w(entire.io entire.com), &(host == &1 or String.ends_with?(host, "." <> &1)))

  defp trusted_host?(_), do: false

  defp trusted_clone_url?(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.scheme == "entire" and is_nil(uri.port) and is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
      trusted_host?(uri.host)
  end

  defp trusted_clone_url?(_), do: false

  defp trusted_jwks_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    trusted_origin?(URI.to_string(%{uri | path: nil})) and uri.path == "/.well-known/jwks.json"
  end

  defp trusted_jwks_url?(_), do: false

  defp cached(key, fetch, refresh \\ false) do
    case if(refresh, do: nil, else: KeyValueStore.get(key)) do
      nil ->
        case fetch.() do
          {:ok, _} = result ->
            KeyValueStore.put(key, result, ttl: to_timeout(minute: 5))
            result

          error ->
            error
        end

      result ->
        result
    end
  end
end
