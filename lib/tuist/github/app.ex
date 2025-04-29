defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore

  def get_app_installation_token_for_repository(repository_full_handle, opts \\ []) do
    ttl = to_timeout(minute: 10)

    case KeyValueStore.get_or_update(
           [__MODULE__, "github_app_token", repository_full_handle],
           [
             cache: get_cache(opts),
             ttl: Keyword.get(opts, :ttl, ttl)
           ],
           fn ->
             refresh_token(repository_full_handle, expires_in: ttl)
           end
         ) do
      {:ok, token} ->
        {:ok, token}

      {:error, error} ->
        {:error, error}
    end
  end

  def clear_token(opts \\ []) do
    opts |> get_cache() |> Cachex.clear()
  end

  def get_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  def refresh_token(repository_full_handle, opts \\ []) do
    private_key = JOSE.JWK.from_pem(Environment.github_app_private_key())

    now = DateTime.to_unix(DateTime.utc_now())

    # Converted to seconds
    expires_in = trunc(Keyword.get(opts, :expires_in, to_timeout(minute: 10)) / 1000)

    # JSON Web Token (JWT)
    claims = %{
      "iat" => now,
      "exp" => now + expires_in,
      "iss" => Environment.github_app_client_id()
    }

    {_, jwt} =
      private_key
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    headers =
      [
        {"Accept", "application/vnd.github.v3+json"},
        {"Authorization", "Bearer #{jwt}"}
      ]

    with {:access_tokens_url, {:ok, %Req.Response{status: 200, body: %{"access_tokens_url" => access_tokens_url}}}} <-
           {:access_tokens_url,
            Req.get("https://api.github.com/repos/#{repository_full_handle}/installation",
              headers: headers,
              finch: Tuist.Finch
            )},
         {:token,
          {:ok,
           %Req.Response{
             status: 201,
             body: %{"token" => token, "expires_at" => expires_at}
           }}} <-
           {:token, Req.post(access_tokens_url, headers: headers, finch: Tuist.Finch)} do
      {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)

      {:ok, %{token: token, expires_at: expires_at}}
    else
      {:access_tokens_url, {:ok, %Req.Response{status: 404}}} ->
        {:error, "The Tuist GitHub app is not installed for #{repository_full_handle}."}

      {:access_tokens_url, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error, "Unexpected status code when getting the access token url: #{status}. Body: #{Jason.encode!(body)}"}

      {:access_tokens_url, {:error, reason}} ->
        {:error, "Request failed when getting the access token url: #{inspect(reason)}"}

      {:token, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error, "Unexpected status code when getting the token: #{status}. Body: #{Jason.encode!(body)}"}

      {:token, {:error, reason}} ->
        {:error, "Request failed when getting the token: #{inspect(reason)}"}
    end
  end
end
