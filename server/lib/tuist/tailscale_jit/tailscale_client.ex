defmodule Tuist.TailscaleJIT.TailscaleClient do
  @moduledoc """
  Tailscale API client. The bot reads tailnet user metadata (role +
  identity) to make policy decisions; we do NOT write to the
  tailnet ACL from the bot. The ACL is a static document edited
  through code review in `infra/tailscale/acls.json`, and runtime
  elevation is handled by the Pomerium gateway against a Tuist DB
  flag, not by mutating policy.

  Two surfaces:

    * `user_role/1` — `{:ok, role}` for an email's tailnet role,
      or `{:error, :not_found}` if the email isn't on the tailnet.
    * `list_users/1` — raw `GET /tailnet/-/users` payload, cached
      for #{30}s in `:persistent_term`.

  Token is OAuth client-credentials with `users:read` scope; the
  bot caches it in `:persistent_term` until expiry.
  """

  alias Tuist.Environment

  @api_base "https://api.tailscale.com/api/v2"
  @token_url @api_base <> "/oauth/token"
  @token_cache_key {__MODULE__, :token}
  @users_cache_key {__MODULE__, :users}

  # Only `users:read` is required after the Pomerium pivot. The
  # bot no longer writes the tailnet ACL, so `policy_file:write`
  # is intentionally absent — the OAuth client should be created
  # with `users:read` only as a least-privilege measure.
  @oauth_scopes "users:read"

  # Cache the tailnet users list briefly. Role changes are
  # infrequent and a stale-by-30s read is fine; this avoids a HTTP
  # round-trip on every Slack interactive click.
  @users_cache_ttl_seconds 30

  @doc """
  Returns `{:ok, role}` where role is one of `:owner`, `:admin`,
  `:network_admin`, `:it_admin`, `:auditor`, `:billing_admin`,
  `:member`, or `{:error, :not_found}` if `email` is not on the
  tailnet. Role-from-tailnet is the source of truth the JIT policy
  uses to decide who can self-approve and who can act as the second
  human; see `Tuist.TailscaleJIT.Policy` for the mapping.
  """
  def user_role(email) when is_binary(email) do
    with {:ok, users} <- list_users() do
      case Enum.find(users, fn u -> Map.get(u, "loginName") == email end) do
        nil -> {:error, :not_found}
        user -> {:ok, parse_role(Map.get(user, "role"))}
      end
    end
  end

  def user_role(_), do: {:error, :not_found}

  @doc """
  Fetches `GET /tailnet/-/users` and returns the raw user list.
  Cached in `:persistent_term` for #{@users_cache_ttl_seconds}s so
  Slack interactive callbacks don't pay a round-trip per click.
  """
  def list_users(opts \\ []) do
    tailnet = Keyword.get(opts, :tailnet, tailnet())

    case :persistent_term.get(@users_cache_key, nil) do
      {^tailnet, users, expires_at} ->
        if DateTime.before?(DateTime.utc_now(), expires_at) do
          {:ok, users}
        else
          fetch_and_cache_users(tailnet)
        end

      _ ->
        fetch_and_cache_users(tailnet)
    end
  end

  defp fetch_and_cache_users(tailnet) do
    with {:ok, token} <- token() do
      url = "#{@api_base}/tailnet/#{tailnet}/users"

      url
      |> Req.get(headers: bearer(token) ++ [{"Accept", "application/json"}])
      |> handle_list_users(tailnet)
    end
  end

  defp handle_list_users({:ok, %Req.Response{status: 200, body: body}}, tailnet) do
    users = Map.get(body, "users", [])
    expires_at = DateTime.add(DateTime.utc_now(), @users_cache_ttl_seconds, :second)
    :persistent_term.put(@users_cache_key, {tailnet, users, expires_at})
    {:ok, users}
  end

  defp handle_list_users({:ok, %Req.Response{status: status, body: body}}, _tailnet) do
    {:error, {:list_users_failed, status, body}}
  end

  defp handle_list_users({:error, reason}, _tailnet) do
    {:error, {:list_users_error, reason}}
  end

  # Tailscale's users endpoint returns role as a hyphenated string.
  # Map to atoms the policy code can pattern-match on. Unknown role
  # strings degrade to `:member` (the lowest-trust real role) so a
  # new Tailscale role we haven't seen doesn't accidentally promote.
  defp parse_role("owner"), do: :owner
  defp parse_role("admin"), do: :admin
  defp parse_role("network-admin"), do: :network_admin
  defp parse_role("it-admin"), do: :it_admin
  defp parse_role("auditor"), do: :auditor
  defp parse_role("billing-admin"), do: :billing_admin
  defp parse_role("member"), do: :member
  defp parse_role(_), do: :member

  defp token do
    case :persistent_term.get(@token_cache_key, nil) do
      {token, expires_at} ->
        if DateTime.before?(DateTime.utc_now(), expires_at) do
          {:ok, token}
        else
          fetch_and_cache_token()
        end

      nil ->
        fetch_and_cache_token()
    end
  end

  defp fetch_and_cache_token do
    # Tailscale's OAuth endpoint expects client_id + client_secret in
    # the form-encoded request body (RFC 6749 §4.4.2-style client
    # credentials grant). Their published curl example does NOT use
    # Basic auth, and an earlier attempt with Basic returned 401
    # "API token invalid" against valid credentials — so the body
    # is the load-bearing path.
    body = %{
      grant_type: "client_credentials",
      scope: @oauth_scopes,
      client_id: client_id(),
      client_secret: client_secret()
    }

    @token_url
    |> Req.post(form: body, headers: [{"Accept", "application/json"}])
    |> handle_token_response()
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    access_token = body["access_token"]
    expires_in = body["expires_in"] || 3600
    # Refresh 60s before actual expiry so an in-flight request
    # cannot use a token that expires mid-call.
    expires_at = DateTime.add(DateTime.utc_now(), expires_in - 60, :second)
    :persistent_term.put(@token_cache_key, {access_token, expires_at})
    {:ok, access_token}
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:token_request_failed, status, body}}
  end

  defp handle_token_response({:error, reason}) do
    {:error, {:token_request_error, reason}}
  end

  defp bearer(token), do: [{"Authorization", "Bearer #{token}"}]

  defp client_id, do: Environment.tailscale_jit_client_id()
  defp client_secret, do: Environment.tailscale_jit_client_secret()
  defp tailnet, do: Environment.tailscale_jit_tailnet() || "-"
end
