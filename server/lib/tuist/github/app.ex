defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment
  alias Tuist.GitHub.Retry
  alias Tuist.KeyValueStore
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS

  # github.com is a known public host; skip the DNS pin to avoid the
  # extra resolution on the hot path. Any other host (i.e. a self-hosted
  # GitHub Enterprise Server) is user-supplied and gets pinned to a public
  # IP at request time as SSRF protection.
  @default_api_url "https://api.github.com"

  def get_installation_token(installation_id, opts \\ []) do
    ttl = to_timeout(minute: 10)
    api_url = Keyword.get(opts, :api_url, VCS.api_url(:github, nil))

    case KeyValueStore.get_or_update(
           [__MODULE__, "installation_token", api_url, installation_id],
           [
             cache: get_cache(opts),
             ttl: Keyword.get(opts, :ttl, ttl)
           ],
           fn ->
             refresh_installation_token(installation_id, api_url: api_url, expires_in: ttl)
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

  defp generate_app_jwt(opts) do
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

    jwt
  end

  defp refresh_installation_token(installation_id, opts) do
    jwt = generate_app_jwt(opts)
    api_url = Keyword.get(opts, :api_url, VCS.api_url(:github, nil))
    url = "#{api_url}/app/installations/#{installation_id}/access_tokens"

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    with {:ok, request_url, ssrf_opts} <- pin_ghes_url(url, api_url) do
      req_opts =
        [
          url: request_url,
          headers: headers,
          finch: Tuist.Finch
        ] ++ ssrf_opts ++ Retry.retry_options()

      handle_token_response(Req.post(req_opts))
    end
  end

  defp handle_token_response({:ok, %Req.Response{status: 201, body: %{"token" => token, "expires_at" => expires_at}}}) do
    {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)
    {:ok, %{token: token, expires_at: expires_at}}
  end

  defp handle_token_response({:ok, %Req.Response{status: _status, body: _body}}) do
    {:error, "Failed to get installation token"}
  end

  defp handle_token_response({:error, %Req.HTTPError{} = error}) do
    {:error, "GitHub API connection error: #{inspect(error.reason)}"}
  end

  defp handle_token_response({:error, error}) do
    {:error, "Unexpected error getting installation token: #{inspect(error)}"}
  end

  # Pin GHES URLs to a public IP to defend against DNS rebinding /
  # SSRF; github.com is treated as a known public host and skips the pin.
  defp pin_ghes_url(url, @default_api_url), do: {:ok, url, []}

  defp pin_ghes_url(url, _api_url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned_url, hostname} ->
        {:ok, pinned_url, [connect_options: SSRFGuard.connect_options(hostname)]}

      {:error, reason} ->
        {:error, "GitHub Enterprise Server host failed SSRF check: #{inspect(reason)}"}
    end
  end
end
