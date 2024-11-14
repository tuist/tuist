defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment

  @cache_key "github_app_token"

  def get_app_installation_token_for_repository(repository_full_handle, opts \\ []) do
    cache = opts |> get_cache()
    ttl = opts |> Keyword.get(:ttl, :timer.minutes(10))

    result =
      Cachex.fetch(cache, @cache_key <> "_#{repository_full_handle}", fn ->
        case refresh_token(repository_full_handle, expires_in: ttl) do
          {:ok, token} -> {:commit, token, expire: ttl}
          {:error, message} -> {:error, message}
        end
      end)

    case result do
      {:commit, token} ->
        {:ok, token}

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
    private_key =
      Environment.github_app_private_key()
      |> JOSE.JWK.from_pem()

    now = DateTime.utc_now() |> DateTime.to_unix()

    # Converted to seconds
    expires_in = trunc(Keyword.get(opts, :expires_in, :timer.minutes(10)) / 1000)

    # JSON Web Token (JWT)
    claims = %{
      "iat" => now,
      "exp" => now + expires_in,
      "iss" => Environment.github_app_client_id()
    }

    {_, jwt} =
      JOSE.JWT.sign(private_key, %{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    headers =
      [
        {"Accept", "application/vnd.github.v3+json"},
        {"Authorization", "Bearer #{jwt}"}
      ]

    with {:access_tokens_url,
          {:ok, %Req.Response{status: 200, body: %{"access_tokens_url" => access_tokens_url}}}} <-
           {:access_tokens_url,
            Req.get("https://api.github.com/repos/#{repository_full_handle}/installation",
              headers: headers
            )},
         {:token,
          {:ok,
           %Req.Response{
             status: 201,
             body: %{"token" => token, "expires_at" => expires_at}
           }}} <-
           {:token, Req.post(access_tokens_url, headers: headers)} do
      {:ok, expires_at, _} =
        expires_at
        |> DateTime.from_iso8601()

      {:ok, %{token: token, expires_at: expires_at}}
    else
      {:access_tokens_url, {:ok, %Req.Response{status: 404}}} ->
        {:error, "The Tuist GitHub app is not installed for #{repository_full_handle}."}

      {:access_tokens_url, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error,
         "Unexpected status code when getting the access token url: #{status}. Body: #{Jason.encode!(body)}"}

      {:access_tokens_url, {:error, reason}} ->
        {:error, "Request failed when getting the access token url: #{inspect(reason)}"}

      {:token, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error,
         "Unexpected status code when getting the token: #{status}. Body: #{Jason.encode!(body)}"}

      {:token, {:error, reason}} ->
        {:error, "Request failed when getting the token: #{inspect(reason)}"}
    end
  end
end
