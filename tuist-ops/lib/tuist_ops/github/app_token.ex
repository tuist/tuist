defmodule TuistOps.GitHub.AppToken do
  @moduledoc """
  Mints and caches GitHub App installation tokens for GitHub workflow calls.
  """

  alias TuistOps.Environment

  @cache_key {__MODULE__, :installation_token}
  @github_api_url "https://api.github.com"
  @jwt_ttl_seconds 600
  @refresh_margin_seconds 60

  def token(opts \\ []) do
    cache_key = cache_key(opts)

    case cached_token(cache_key) do
      {:ok, token} -> {:ok, token}
      :miss -> refresh_token(cache_key)
    end
  end

  def clear_cache(opts \\ []) do
    opts
    |> cache_key()
    |> :persistent_term.erase()

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp cache_key(opts) do
    Keyword.get(opts, :cache_key, @cache_key)
  end

  defp cached_token(cache_key) do
    case :persistent_term.get(cache_key, nil) do
      {token, expires_at} when is_binary(token) ->
        refresh_after = DateTime.add(DateTime.utc_now(), @refresh_margin_seconds, :second)

        if DateTime.compare(expires_at, refresh_after) == :gt do
          {:ok, token}
        else
          :miss
        end

      _ ->
        :miss
    end
  end

  defp refresh_token(cache_key) do
    with {:ok, credentials} <- credentials(),
         {:ok, jwt} <- app_jwt(credentials) do
      credentials.installation_id
      |> token_url()
      |> Req.post(headers: app_headers(jwt))
      |> handle_token_response(cache_key)
    end
  end

  defp credentials do
    with {:ok, app_id} <- required_env(Environment.github_app_id(), "GITHUB_APP_ID"),
         {:ok, installation_id} <-
           required_env(Environment.github_app_installation_id(), "GITHUB_APP_INSTALLATION_ID"),
         {:ok, private_key} <-
           required_env(Environment.github_app_private_key(), "GITHUB_APP_PRIVATE_KEY") do
      {:ok,
       %{
         app_id: app_id,
         installation_id: installation_id,
         private_key: normalize_private_key(private_key)
       }}
    end
  end

  defp required_env(value, name) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:missing_env, name}}
      trimmed_value -> {:ok, trimmed_value}
    end
  end

  defp required_env(_value, name), do: {:error, {:missing_env, name}}

  defp normalize_private_key(private_key) do
    String.replace(private_key, "\\n", "\n")
  end

  defp app_jwt(%{app_id: app_id, private_key: private_key}) do
    private_key = JOSE.JWK.from_pem(private_key)
    now = DateTime.to_unix(DateTime.utc_now())

    claims = %{
      "iat" => now - 60,
      "exp" => now + @jwt_ttl_seconds,
      "iss" => app_id
    }

    {_meta, jwt} =
      private_key
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    {:ok, jwt}
  rescue
    error -> {:error, {:invalid_private_key, Exception.message(error)}}
  end

  defp token_url(installation_id) do
    "#{@github_api_url}/app/installations/#{installation_id}/access_tokens"
  end

  defp app_headers(jwt) do
    [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]
  end

  defp handle_token_response(
         {:ok, %Req.Response{status: 201, body: %{"token" => token, "expires_at" => expires_at}}},
         cache_key
       )
       when is_binary(token) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, expires_at, _offset} ->
        :persistent_term.put(cache_key, {token, expires_at})
        {:ok, token}

      {:error, reason} ->
        {:error, {:invalid_expires_at, reason}}
    end
  end

  defp handle_token_response({:ok, %Req.Response{status: 201, body: body}}, _cache_key) do
    {:error, {:invalid_response, body}}
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}, _cache_key) do
    {:error, {:github_status, status, body}}
  end

  defp handle_token_response({:error, reason}, _cache_key) do
    {:error, {:github_error, reason}}
  end
end
