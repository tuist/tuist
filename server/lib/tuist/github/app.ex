defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment
  alias Tuist.GitHub.Retry
  alias Tuist.KeyValueStore

  def get_installation_token(installation_id, opts \\ []) do
    ttl = to_timeout(minute: 10)

    case KeyValueStore.get_or_update(
           [__MODULE__, "installation_token", installation_id],
           [
             cache: get_cache(opts),
             ttl: Keyword.get(opts, :ttl, ttl)
           ],
           fn ->
             refresh_installation_token(installation_id, expires_in: ttl)
           end
         ) do
      {:ok, token} ->
        {:ok, token}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Resolves the GitHub App installation_id for a repo by asking
  GitHub directly. Returns `{:ok, installation_id}` (an integer)
  on success, `{:error, reason}` otherwise.

  Cached for 6 h via `KeyValueStore` because installation_ids are
  stable in normal operation — they only change on deliberate ops
  actions (uninstall + reinstall, App rotation). The TTL bounds
  staleness on the rare case where they do change.

  Used by `Tuist.Runners.Reconciler` to mint JIT runner configs
  without the chart needing to enumerate installation_ids per
  customer pool.
  """
  def get_installation_id_for_repo(owner, repo, opts \\ []) when is_binary(owner) and is_binary(repo) do
    ttl = Keyword.get(opts, :ttl, to_timeout(hour: 6))

    KeyValueStore.get_or_update(
      [__MODULE__, "installation_id_for_repo", owner, repo],
      [cache: get_cache(opts), ttl: ttl],
      fn ->
        refresh_installation_id_for_repo(owner, repo, expires_in: to_timeout(minute: 10))
      end
    )
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

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    req_opts =
      [
        url: "https://api.github.com/app/installations/#{installation_id}/access_tokens",
        headers: headers,
        finch: Tuist.Finch
      ] ++ Retry.retry_options()

    case Req.post(req_opts) do
      {:ok, %Req.Response{status: 201, body: %{"token" => token, "expires_at" => expires_at}}} ->
        {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)
        {:ok, %{token: token, expires_at: expires_at}}

      {:ok, %Req.Response{status: _status, body: _body}} ->
        {:error, "Failed to get installation token"}

      {:error, %Req.HTTPError{} = error} ->
        {:error, "GitHub API connection error: #{inspect(error.reason)}"}

      {:error, error} ->
        {:error, "Unexpected error getting installation token: #{inspect(error)}"}
    end
  end

  defp refresh_installation_id_for_repo(owner, repo, opts) do
    jwt = generate_app_jwt(opts)

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    req_opts =
      [
        url: "https://api.github.com/repos/#{owner}/#{repo}/installation",
        headers: headers,
        finch: Tuist.Finch
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} when is_integer(id) ->
        {:ok, id}

      {:ok, %Req.Response{status: 404}} ->
        # The Tuist App is not installed on this repo — possible
        # during a fresh staging cluster bring-up before the App
        # is granted access, or if a customer's pool config
        # references a repo without an active install.
        {:error, :not_installed}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Failed to resolve installation_id (HTTP #{status}): #{inspect(body)}"}

      {:error, %Req.HTTPError{} = error} ->
        {:error, "GitHub API connection error: #{inspect(error.reason)}"}

      {:error, error} ->
        {:error, "Unexpected error resolving installation_id: #{inspect(error)}"}
    end
  end
end
