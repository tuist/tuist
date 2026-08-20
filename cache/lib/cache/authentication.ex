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
    end
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

  # Grants are complete and say which action they cover, so they are the whole
  # answer. Tuist's server mints these; the shape is agreed with the cache
  # nodes that read them back.
  defp verify_granted_project(grants, claims, requested_handle, action) do
    if granted?(grants, requested_handle, action) do
      {:ok, calculate_ttl(Map.get(claims, "exp"))}
    else
      {:error, :not_granted}
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
    |> Cachex.fetch(cache_key, fn -> fetch_projects(cache_key, options) end)
    |> unwrap_fetch_result()
  end

  defp fetch_projects(cache_key, options) do
    start_time = System.monotonic_time()
    :telemetry.execute([:cache, :auth, :server, :request], %{}, %{})

    result = Req.get(options)

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:cache, :auth, :server, :response], %{duration: duration}, %{})

    case result do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        result = project_access_result(cache_key, projects)
        ttl = if result == :ok, do: success_ttl(), else: failure_ttl()
        {:commit, result, expire: ttl}

      {:ok, %{status: 403}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :forbidden})
        {:commit, {:error, 403, "You don't have access to this project"}, expire: failure_ttl()}

      {:ok, %{status: 401}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :unauthorized})
        {:commit, {:error, 401, "Unauthorized"}, expire: failure_ttl()}

      {:ok, %{status: status}} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: "status_#{status}"})
        {:ignore, {:error, status, "Server responded with status #{status}"}}

      {:error, reason} ->
        :telemetry.execute([:cache, :auth, :server, :error], %{}, %{reason: :network_error})
        Logger.warning("Failed to fetch accessible projects: #{inspect(reason)}")
        {:ignore, {:error, 500, "Failed to fetch accessible projects"}}
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

    case Plug.Conn.get_req_header(conn, "x-request-id") do
      [request_id | _] -> [{"x-request-id", request_id} | base_headers]
      _ -> base_headers
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
      [url: url, headers: headers, finch: Cache.Finch, retry: false, cache: false],
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

  def generate_cache_key(auth_header) do
    :sha256
    |> :crypto.hash(auth_header)
    |> Base.encode16(case: :lower)
  end

  defp project_access_result({_auth_key, requested_handle, _action}, projects) do
    project_handles =
      projects
      |> Enum.map(fn
        handle when is_binary(handle) -> String.downcase(handle)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.member?(project_handles, requested_handle) do
      :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :server})
      :ok
    else
      {:error, 403, "You don't have access to this project"}
    end
  end

  defp cache_result(cache, cache_key, result, ttl) do
    Cachex.put(cache, cache_key, result, ttl: ttl)
    result
  end

  defp full_handle(account_handle, project_handle) do
    String.downcase("#{account_handle}/#{project_handle}")
  end
end
