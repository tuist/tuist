defmodule Cache.Authentication do
  @moduledoc """
  Authentication for CAS operations.

  This module validates that a request has proper authorization to access a project
  by first attempting to decode JWT tokens locally and extract the projects claim.
  For non-JWT tokens (e.g., project tokens), it falls back to calling the server's
  /api/cache/access endpoint and caching the results. That endpoint resolves
  cache access specifically, so an account that has exhausted the free tier is
  already absent from what it returns.
  """

  require Logger

  @failure_cache_ttl 3
  @success_cache_ttl 600
  # How long a settled server answer may still be served while the server
  # cannot answer, counted from when it was confirmed. Matches Kura.
  @confirmed_cache_ttl 1500
  @unavailable_backoff 3
  @request_timeout_ms 3_000
  @pool_timeout_ms 1_000
  @cache_name :cas_auth_cache

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@cache_name, []]}
    }
  end

  def cache_name, do: @cache_name

  @doc """
  Ensures the request has access to the specified project.

  Returns `{:ok, auth_header}` if authorized, or `{:error, status, message}` otherwise.
  """
  def ensure_project_accessible(conn, account_handle, project_handle, opts \\ []) do
    auth_header = conn |> Plug.Conn.get_req_header("authorization") |> List.first()
    cache = Keyword.get(opts, :cache_name, cache_name())

    if is_nil(auth_header) do
      {:error, 401, "Missing Authorization header"}
    else
      requested_handle = full_handle(account_handle, project_handle)

      case authorize(auth_header, requested_handle, conn, cache) do
        :ok ->
          {:ok, auth_header}

        {:error, status, message} ->
          {:error, status, message}
      end
    end
  end

  defp authorize(auth_header, requested_handle, conn, cache) do
    # Keyed by action as well as token and handle: a token can be granted the
    # read and not the write, so a decision reached for one must never be
    # replayed for the other.
    cache_key = {generate_cache_key(auth_header), requested_handle, request_action(conn)}

    case Cachex.get(cache, cache_key) do
      {:ok, nil} ->
        :telemetry.execute([:cache, :auth, :cache, :miss], %{}, %{})
        authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache)

      {:ok, result} ->
        :telemetry.execute([:cache, :auth, :cache, :hit], %{}, %{})
        if result == :ok, do: :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :cache})
        result

      _ ->
        :telemetry.execute([:cache, :auth, :cache, :miss], %{}, %{})
        authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache)
    end
  end

  defp authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache) do
    token = extract_token(auth_header)
    {_token_key, _handle, action} = cache_key

    case verify_jwt(token, requested_handle, action) do
      {:ok, ttl} ->
        :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :jwt})
        cache_result(cache, cache_key, :ok, ttl)

      {:error, :not_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, conn, cache)

      {:error, :project_not_in_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, conn, cache)

      # A token carrying grants has already had its say, so this is the answer
      # rather than a reason to ask the server. Asking would also be futile:
      # the server does not accept a cache token as a credential, so the
      # fallback turns every ungranted request into a misleading 401.
      {:error, :not_granted} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :forbidden})
        cache_result(cache, cache_key, {:error, 403, "You don't have access to this project"}, failure_ttl())

      {:error, :payment_required, account_handle} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :payment_required})
        cache_result(cache, cache_key, payment_required_error(account_handle), failure_ttl())
    end
  end

  # An exhausted plan reaches a node as absence from the grants, which alone is
  # indistinguishable from never having had access. The server names the
  # accounts it withheld for payment so the caller is told what is actually
  # wrong and what to do about it.
  defp payment_required_error(account_handle) do
    {:error, 402,
     "The account '#{account_handle}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'."}
  end

  defp payment_required?(handles, account_handle) when is_list(handles) do
    Enum.any?(handles, fn handle ->
      is_binary(handle) and String.downcase(handle) == String.downcase(account_handle)
    end)
  end

  defp payment_required?(_handles, _account_handle), do: false

  defp account_handle_of(requested_handle) do
    requested_handle |> String.split("/") |> List.first()
  end

  defp request_action(%Plug.Conn{method: method}) when method in ["GET", "HEAD"], do: :read
  defp request_action(_conn), do: :write

  defp extract_token("Bearer " <> token), do: token
  defp extract_token(token), do: token

  defp verify_jwt(token, requested_handle, action) do
    if Cache.Config.guardian_configured?() do
      do_verify_jwt(token, requested_handle, action)
    else
      {:error, :not_jwt}
    end
  end

  defp do_verify_jwt(token, requested_handle, action) do
    case Cache.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        verify_project_access(claims, requested_handle, action)

      {:error, _reason} ->
        {:error, :not_jwt}
    end
  end

  defp verify_project_access(claims, requested_handle, action) do
    case Map.get(claims, "cache_grants") do
      nil -> verify_listed_project(claims, requested_handle)
      grants -> verify_granted_project(grants, claims, requested_handle, action)
    end
  end

  # The projects claim lists what the token reaches without saying what it may
  # do there, and it is capped, so a handle missing from it is inconclusive and
  # falls through to the server.
  defp verify_listed_project(claims, requested_handle) do
    projects = Map.get(claims, "projects", [])
    exp = Map.get(claims, "exp")

    if requested_handle in projects do
      {:ok, calculate_ttl(exp)}
    else
      {:error, :project_not_in_jwt}
    end
  end

  # Grants say which action they cover, so for a project they name they are the
  # whole answer. Tuist's server mints these; the shape is agreed with the cache
  # nodes that read them back.
  #
  # A cache token's grants are complete. An access token's cover only the
  # subject's most recently used projects when it was minted, so a project they
  # leave out may still be reachable and is asked of the server.
  defp verify_granted_project(grants, claims, requested_handle, action) do
    account_handle = account_handle_of(requested_handle)

    cond do
      granted?(grants, requested_handle, action) ->
        {:ok, calculate_ttl(Map.get(claims, "exp"))}

      payment_required?(Map.get(claims, "cache_payment_required", []), account_handle) ->
        {:error, :payment_required, account_handle}

      Map.get(claims, "typ") == "cache" or granted?(grants, requested_handle, :read) ->
        {:error, :not_granted}

      true ->
        {:error, :project_not_in_jwt}
    end
  end

  # A request naming a project is answered by the project bucket alone: an
  # account grant is access to the account's own cache, not to every project
  # in it.
  defp granted?(grants, requested_handle, action) do
    bucket = grants |> grant_bucket("project") |> granted_handles(action)

    requested_handle in bucket
  end

  defp grant_bucket(grants, scope) when is_map(grants) do
    case Map.get(grants, scope) do
      bucket when is_map(bucket) -> bucket
      _ -> %{}
    end
  end

  defp grant_bucket(_grants, _scope), do: %{}

  # Write implies read, so a writer never has to be granted both.
  defp granted_handles(bucket, :read), do: handles(bucket, "read") ++ handles(bucket, "write")
  defp granted_handles(bucket, :write), do: handles(bucket, "write")

  # Handles compare lowercased, and an empty handle counts as absent rather
  # than as a handle named "".
  defp handles(bucket, action) do
    case Map.get(bucket, action) do
      handles when is_list(handles) ->
        handles
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp calculate_ttl(nil), do: success_ttl()

  defp calculate_ttl(exp) when is_integer(exp) do
    now = System.system_time(:second)
    seconds_until_expiry = exp - now

    if seconds_until_expiry > 0 do
      to_timeout(second: min(seconds_until_expiry, @success_cache_ttl))
    else
      to_timeout(second: 0)
    end
  end

  defp calculate_ttl(_), do: success_ttl()

  defp fetch_and_cache_projects(auth_header, cache_key, conn, cache) do
    headers = build_headers(auth_header, conn)
    options = request_options(headers)

    cache
    |> Cachex.fetch(cache_key, fn -> fetch_projects(cache, cache_key, options) end)
    |> unwrap_fetch_result()
  end

  # Settled answers (an allowed request, or a write refused on a readable
  # project) are also kept under a confirmed key for longer than they are
  # fresh, and served from there only while the server cannot answer, so an
  # outage does not fail every build. Only a fresh answer writes the confirmed
  # key, so the window counts from the server's last confirmation and serving
  # it never extends it. Any other definitive answer deletes the confirmed keys
  # of both actions, and a 401 voids every confirmed key of that credential
  # through its marker.
  defp fetch_projects(cache, cache_key, options) do
    start_time = System.monotonic_time()
    :telemetry.execute([:cache, :auth, :server, :request], %{}, %{})

    # Finch raises when no connection can be checked out in time, which is
    # what a server that drops packets leads to; it is an outage like any other.
    result =
      try do
        Req.get(options)
      rescue
        error -> {:error, error}
      end

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:cache, :auth, :server, :response], %{duration: duration}, %{})

    handle_server_response(cache, cache_key, result)
  end

  defp handle_server_response(cache, cache_key, result) do
    case result do
      {:ok, %{status: 200, body: %{} = body}} when is_map_key(body, "projects") or is_map_key(body, "cache_grants") ->
        {result, ttl} = project_access_result(cache_key, body)

        if ttl == success_ttl() do
          confirm(cache, cache_key, result)
        else
          forget_confirmed(cache, cache_key)
        end

        {:commit, result, ttl: ttl}

      {:ok, %{status: 403}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :forbidden})
        forget_confirmed(cache, cache_key)
        {:commit, {:error, 403, "You don't have access to this project"}, ttl: failure_ttl()}

      {:ok, %{status: 401}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :unauthorized})
        forget_confirmed(cache, cache_key)
        invalidate_credential(cache, cache_key)
        {:commit, {:error, 401, "Unauthorized"}, ttl: failure_ttl()}

      {:ok, %{status: status}} when status in [200, 500, 502, 503, 504] ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: "status_#{status}"})
        without_server(cache, cache_key)

      {:ok, %{status: status}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: "status_#{status}"})
        {:ignore, {:error, status, "Server responded with status #{status}"}}

      {:error, reason} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :network_error})
        Logger.warning("Failed to fetch accessible projects: #{inspect(reason)}")
        without_server(cache, cache_key)
    end
  end

  # Under the marker's lock, so an answer sent before a 401 on another key of
  # the same credential cannot mark a revoked credential valid again.
  defp confirm(cache, {token_key, _handle, _action} = cache_key, result) do
    Cachex.transaction(cache, [{:credential, token_key}], fn worker ->
      case Cachex.get(worker, {:credential, token_key}) do
        {:ok, :invalid} ->
          :ok

        _ ->
          Cachex.put(worker, {:confirmed, cache_key}, result, ttl: confirmed_ttl())
          Cachex.put(worker, {:credential, token_key}, :valid, ttl: confirmed_ttl())
      end
    end)
  end

  # Update only: a marker written for every unknown token would keep one
  # entry per random token for the whole confirmed window.
  defp invalidate_credential(cache, {token_key, _handle, _action}) do
    Cachex.transaction(cache, [{:credential, token_key}], fn worker ->
      Cachex.update(worker, {:credential, token_key}, :invalid)
    end)
  end

  # Refused reads mean refused writes, and a write is refused here only when
  # the project is not readable either, so both actions lose their answer.
  defp forget_confirmed(cache, {token_key, handle, _action}) do
    Cachex.del(cache, {:confirmed, {token_key, handle, :read}})
    Cachex.del(cache, {:confirmed, {token_key, handle, :write}})
  end

  # A stale answer is committed for no longer than its confirmed key has left,
  # so requests in the meantime do not each ask a server that is down. Without
  # one, the 503 is not kept: clients retry it, and the first retry after a
  # short blip should reach the server rather than a remembered failure.
  defp without_server(cache, {token_key, _handle, _action} = cache_key) do
    with {:ok, credential} when credential != :invalid <- Cachex.get(cache, {:credential, token_key}),
         {:ok, confirmed} when not is_nil(confirmed) <- Cachex.get(cache, {:confirmed, cache_key}),
         {:ok, remaining} when is_integer(remaining) and remaining > 0 <- Cachex.ttl(cache, {:confirmed, cache_key}) do
      :telemetry.execute([:cache, :auth, :server, :stale], %{}, %{})
      {:commit, confirmed, ttl: min(unavailable_backoff(), remaining)}
    else
      _ -> {:ignore, {:error, 503, "Authentication backend unavailable"}}
    end
  end

  defp unwrap_fetch_result({:ok, result}), do: result
  defp unwrap_fetch_result({:commit, result}), do: result
  defp unwrap_fetch_result({:commit, result, _options}), do: result
  defp unwrap_fetch_result({:ignore, result}), do: result

  defp unwrap_fetch_result({:error, reason}) do
    Logger.warning("Failed to fetch accessible projects: #{inspect(reason)}")
    {:error, 500, "Failed to fetch accessible projects"}
  end

  defp build_headers(auth_header, conn) do
    base_headers = [{"authorization", auth_header}]

    # The id is the client's: forward it only when it looks like one, so a
    # client cannot send the server arbitrary bytes under a credential whose
    # confirmed answer would be served if the server fails on them.
    case Plug.Conn.get_req_header(conn, "x-request-id") do
      [request_id | _] when byte_size(request_id) in 1..200 ->
        if Regex.match?(~r/\A[A-Za-z0-9._:-]+\z/, request_id),
          do: [{"x-request-id", request_id} | base_headers],
          else: base_headers

      _ ->
        base_headers
    end
  end

  defp request_options(headers) do
    base_url = server_url()
    url = "#{base_url}/api/cache/access"

    req_options =
      Application.get_env(
        :cache,
        :authentication_req_options,
        Application.get_env(:cache, :req_options, [])
      )

    Keyword.merge(
      [
        url: url,
        headers: headers,
        finch: Cache.Finch,
        retry: false,
        cache: false,
        receive_timeout: @request_timeout_ms,
        pool_timeout: @pool_timeout_ms
      ],
      req_options
    )
  end

  def server_url do
    Application.get_env(:cache, :server_url)
  end

  defp success_ttl do
    to_timeout(second: @success_cache_ttl)
  end

  defp failure_ttl do
    to_timeout(second: @failure_cache_ttl)
  end

  defp confirmed_ttl do
    to_timeout(second: @confirmed_cache_ttl)
  end

  defp unavailable_backoff do
    to_timeout(second: @unavailable_backoff)
  end

  def generate_cache_key(auth_header) do
    :sha256
    |> :crypto.hash(auth_header)
    |> Base.encode16(case: :lower)
  end

  defp project_access_result({_auth_key, requested_handle, action}, body) do
    account_handle = account_handle_of(requested_handle)

    cond do
      server_allows?(body, requested_handle, action) ->
        :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :server})
        {:ok, success_ttl()}

      payment_required?(Map.get(body, "payment_required", []), account_handle) ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :payment_required})
        {payment_required_error(account_handle), failure_ttl()}

      # A write the grants refuse on a project they let the credential read is
      # a settled answer, not a transient one: a read-only credential keeps
      # uploading for its whole build, and holding the refusal only as long as
      # other failures would ask the server again every few seconds. It is held
      # as long as an allowed answer is, which is also how long a revocation
      # takes to reach this node.
      read_only_write?(body, requested_handle, action) ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :forbidden})
        {{:error, 403, "You don't have access to this project"}, success_ttl()}

      true ->
        {{:error, 403, "You don't have access to this project"}, failure_ttl()}
    end
  end

  defp read_only_write?(%{"cache_grants" => grants}, requested_handle, :write) do
    granted?(grants, requested_handle, :read)
  end

  defp read_only_write?(_body, _requested_handle, _action), do: false

  # `projects` lists what the credential reaches without saying what it may do
  # there, so a read-only token, a viewer, or a member of an account that keeps
  # writes to tokens is listed alongside writers. The server sends the grants
  # beside it to say which action each project allows, and they decide.
  #
  # A server older than the grants sends `projects` alone, and refusing writes
  # it lists would stop every opaque credential, CI project tokens included,
  # from uploading until the server catches up. Those are answered as before.
  defp server_allows?(%{"cache_grants" => grants}, requested_handle, action) do
    granted?(grants, requested_handle, action)
  end

  defp server_allows?(%{"projects" => projects}, requested_handle, _action) when is_list(projects) do
    Enum.any?(projects, &(is_binary(&1) and String.downcase(&1) == requested_handle))
  end

  defp server_allows?(_body, _requested_handle, _action), do: false

  defp cache_result(cache, cache_key, result, ttl) do
    Cachex.put(cache, cache_key, result, ttl: ttl)
    result
  end

  defp full_handle(account_handle, project_handle) do
    String.downcase("#{account_handle}/#{project_handle}")
  end
end
