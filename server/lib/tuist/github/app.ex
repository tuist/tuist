defmodule Tuist.GitHub.App do
  @moduledoc """
  Manages GitHub App authentication: signs the app-level JWT and exchanges
  it for short-lived installation tokens.

  Accepts an optional `installation` so per-installation App credentials
  (registered on a GHES instance via the manifest flow) take precedence
  over the globally-configured env vars. If no installation-scoped
  credentials exist, the env-var-configured github.com App is used.
  """

  alias Tuist.GitHub.Retry
  alias Tuist.KeyValueStore
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS

  def get_installation_token(installation, opts \\ [])

  def get_installation_token(%{installation_id: installation_id} = installation, opts) when is_binary(installation_id) do
    api_url = Keyword.get(opts, :api_url, VCS.installation_api_url(installation))
    creds = Keyword.get(opts, :credentials, VCS.github_app_credentials(installation))
    fetch_installation_token(installation_id, api_url, creds, opts)
  end

  def get_installation_token(installation_id, opts) when is_binary(installation_id) do
    api_url = Keyword.get(opts, :api_url, VCS.api_url(:github, nil))
    creds = Keyword.get(opts, :credentials, VCS.github_app_credentials())
    fetch_installation_token(installation_id, api_url, creds, opts)
  end

  defp fetch_installation_token(_installation_id, _api_url, nil, _opts) do
    {:error, "GitHub App is not configured"}
  end

  defp fetch_installation_token(installation_id, api_url, creds, opts) do
    ttl = to_timeout(minute: 10)

    case KeyValueStore.get_or_update(
           [__MODULE__, "installation_token", api_url, installation_id],
           [
             cache: get_cache(opts),
             ttl: Keyword.get(opts, :ttl, ttl)
           ],
           fn -> refresh_installation_token(installation_id, api_url, creds, expires_in: ttl) end
         ) do
      {:ok, token} -> {:ok, token}
      {:error, error} -> {:error, error}
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

  Used by `TuistWeb.RunnersController.dispatch/2` to mint JIT
  runner configs without the chart needing to enumerate
  installation_ids per customer pool.
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

  @doc """
  Returns the GitHub App installation id for an organization
  account. Used by the runner-pool path, which is org-scoped:
  the runner group's repo allowlist on the GitHub side is the
  source of truth for which repos can consume capacity, so the
  pool itself only needs the org's installation id (one per
  customer org, not one per repo).

  Same 6 h cache + 404 → `{:error, :not_installed}` shape as
  the per-repo variant.
  """
  def get_installation_id_for_org(owner, opts \\ []) when is_binary(owner) do
    ttl = Keyword.get(opts, :ttl, to_timeout(hour: 6))

    KeyValueStore.get_or_update(
      [__MODULE__, "installation_id_for_org", owner],
      [cache: get_cache(opts), ttl: ttl],
      fn ->
        refresh_installation_id_for_org(owner, expires_in: to_timeout(minute: 10))
      end
    )
  end

  def clear_token(opts \\ []) do
    opts |> get_cache() |> Cachex.clear()
  end

  def get_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  defp generate_app_jwt(creds, opts) do
    private_key = JOSE.JWK.from_pem(creds.private_key)

    now = DateTime.to_unix(DateTime.utc_now())

    # Converted to seconds
    expires_in = trunc(Keyword.get(opts, :expires_in, to_timeout(minute: 10)) / 1000)

    claims = %{
      "iat" => now,
      "exp" => now + expires_in,
      "iss" => creds.app_id
    }

    {_, jwt} =
      private_key
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    jwt
  end

  defp refresh_installation_token(installation_id, api_url, creds, opts) do
    jwt = generate_app_jwt(creds, opts)

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    url = "#{api_url}/app/installations/#{installation_id}/access_tokens"

    with {:ok, pinned_url, ssrf_opts} <- pin_for_request(url, api_url) do
      req_opts =
        [
          url: pinned_url,
          headers: headers
        ] ++ ssrf_opts ++ Retry.retry_options()

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
  end

  # Skip SSRF pinning for the canonical github.com REST host; pin every
  # GHES instance, since their hostnames are user-controlled.
  #
  # github.com uses the shared `Tuist.Finch` pool. GHES uses Req's default
  # pool because the per-host `:connect_options` (SNI / cert hostname) are
  # mutually exclusive with a user-supplied `:finch` pool.
  defp pin_for_request(url, "https://api.github.com"), do: {:ok, url, [finch: Tuist.Finch]}

  defp pin_for_request(url, _api_url) do
    case SSRFGuard.pin(url) do
      {:ok, pinned_url, hostname} -> {:ok, pinned_url, [connect_options: SSRFGuard.connect_options(hostname)]}
      {:error, reason} -> {:error, "SSRF guard rejected GHES URL: #{inspect(reason)}"}
    end
  end

  defp refresh_installation_id_for_repo(owner, repo, opts) do
    creds = Keyword.get(opts, :credentials, VCS.github_app_credentials())

    if is_nil(creds) do
      {:error, "GitHub App is not configured"}
    else
      do_refresh_installation_id_for_repo(owner, repo, creds, opts)
    end
  end

  defp do_refresh_installation_id_for_repo(owner, repo, creds, opts) do
    jwt = generate_app_jwt(creds, opts)

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

  defp refresh_installation_id_for_org(owner, opts) do
    creds = Keyword.get(opts, :credentials, VCS.github_app_credentials())

    if is_nil(creds) do
      {:error, "GitHub App is not configured"}
    else
      do_refresh_installation_id_for_org(owner, creds, opts)
    end
  end

  defp do_refresh_installation_id_for_org(owner, creds, opts) do
    jwt = generate_app_jwt(creds, opts)

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    req_opts =
      [
        url: "https://api.github.com/orgs/#{owner}/installation",
        headers: headers,
        finch: Tuist.Finch
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id}}} when is_integer(id) ->
        {:ok, id}

      {:ok, %Req.Response{status: 404}} ->
        # The Tuist App is not installed on this org. Mirrors the
        # per-repo variant's :not_installed signal so pool callers
        # can degrade gracefully (skip reconcile / drop dispatch).
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
