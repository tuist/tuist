defmodule Tuist.TailscaleJIT.TailscaleClient do
  @moduledoc """
  Tailscale Policy File API client. Two operations the bot needs:
  fetch the current ACL document with its ETag, and replace it
  using optimistic concurrency via `If-Match`. Token is OAuth
  client-credentials with `policy_file:write` scope; the bot
  caches it in `:persistent_term` until expiry.

  The 412 (Precondition Failed) retry policy lives in
  `post_acl_with_retry/3` because it composes the GET-modify-POST
  loop the caller actually wants. Callers should prefer that to
  `post_acl/3`.
  """

  alias Tuist.Environment

  @api_base "https://api.tailscale.com/api/v2"
  @token_url @api_base <> "/oauth/token"
  @token_cache_key {__MODULE__, :token}
  @users_cache_key {__MODULE__, :users}

  # The OAuth token request asks for both scopes; the OAuth client
  # in the Tailscale admin console must be created with both
  # `policy_file:write` (for ACL mutation) and `users:read` (so
  # `user_role/1` can map a tailnet identity to its role for policy
  # decisions). If `users:read` is missing the token endpoint still
  # returns a token, but `list_users/0` returns 403.
  @oauth_scopes "policy_file:write users:read"

  # Cache the tailnet users list briefly. Role changes are
  # infrequent and a stale-by-30s read is fine; this avoids a HTTP
  # round-trip on every Slack interactive click.
  @users_cache_ttl_seconds 30

  @retry_backoffs_ms [250, 500, 1000]

  @doc """
  Fetches the ACL as `{:ok, body_text, etag}`. `body_text` is the
  raw HuJSON document (preserved verbatim for the splice path);
  `etag` is opaque, pass it back as-is in `post_acl/3`.
  """
  def get_acl(opts \\ []) do
    tailnet = Keyword.get(opts, :tailnet, tailnet())

    with {:ok, token} <- token() do
      url = "#{@api_base}/tailnet/#{tailnet}/acl"

      url
      |> Req.get(headers: bearer(token) ++ [{"Accept", "application/hujson"}])
      |> handle_get_acl()
    end
  end

  @doc """
  Replaces the ACL with `body` if the current ETag matches `etag`.
  Returns `{:ok, new_etag}` on success or `{:error, :etag_mismatch}`
  on 412. Other failures are `{:error, reason}`.
  """
  def post_acl(body, etag, opts \\ []) when is_binary(body) and is_binary(etag) do
    tailnet = Keyword.get(opts, :tailnet, tailnet())

    with {:ok, token} <- token() do
      url = "#{@api_base}/tailnet/#{tailnet}/acl"

      headers =
        bearer(token) ++
          [
            {"Content-Type", "application/hujson"},
            {"If-Match", etag}
          ]

      url
      |> Req.post(headers: headers, body: body)
      |> handle_post_acl()
    end
  end

  @doc """
  Read-modify-write loop with bounded retry on 412. `mutate` is a
  function `(body_text -> {:ok, new_body} | {:error, reason})`
  that produces the next document from the current one. Returns
  `{:ok, :updated}` or `{:ok, :unchanged}` (when the mutation
  returns the same document and the post is therefore skipped), or
  `{:error, reason}`.
  """
  def update_acl(mutate, opts \\ []) when is_function(mutate, 1) do
    do_update_acl(mutate, opts, @retry_backoffs_ms)
  end

  defp do_update_acl(mutate, opts, backoffs) do
    with {:ok, current, etag} <- get_acl(opts),
         {:ok, next} <- mutate.(current) do
      if next == current do
        {:ok, :unchanged}
      else
        case post_acl(next, etag, opts) do
          {:ok, _new_etag} ->
            {:ok, :updated}

          {:error, :etag_mismatch} ->
            case backoffs do
              [delay | rest] ->
                Process.sleep(delay + :rand.uniform(div(delay, 4)))
                do_update_acl(mutate, opts, rest)

              [] ->
                {:error, :etag_mismatch_exhausted}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

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

  defp handle_get_acl({:ok, %Req.Response{status: 200, body: body, headers: headers}}) do
    body_text =
      case body do
        binary when is_binary(binary) -> binary
        other -> JSON.encode!(other)
      end

    etag = header_value(headers, "etag") || header_value(headers, "ETag")

    if is_nil(etag) do
      {:error, :missing_etag}
    else
      {:ok, body_text, etag}
    end
  end

  defp handle_get_acl({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:get_acl_failed, status, body}}
  end

  defp handle_get_acl({:error, reason}) do
    {:error, {:get_acl_error, reason}}
  end

  defp handle_post_acl({:ok, %Req.Response{status: status, headers: headers}}) when status in 200..299 do
    {:ok, header_value(headers, "etag") || header_value(headers, "ETag")}
  end

  defp handle_post_acl({:ok, %Req.Response{status: 412}}) do
    {:error, :etag_mismatch}
  end

  defp handle_post_acl({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:post_acl_failed, status, body}}
  end

  defp handle_post_acl({:error, reason}) do
    {:error, {:post_acl_error, reason}}
  end

  defp header_value(headers, name) when is_list(headers) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == String.downcase(name) end)
    |> case do
      {_, v} when is_list(v) -> List.first(v)
      {_, v} -> v
      _ -> nil
    end
  end

  defp header_value(headers, name) when is_map(headers) do
    case Map.get(headers, String.downcase(name)) do
      [v | _] -> v
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp bearer(token), do: [{"Authorization", "Bearer #{token}"}]

  defp client_id, do: Environment.tailscale_jit_client_id()
  defp client_secret, do: Environment.tailscale_jit_client_secret()
  defp tailnet, do: Environment.tailscale_jit_tailnet() || "-"
end
