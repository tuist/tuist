defmodule Cache.Authentication do
  @moduledoc """
  Authentication for CAS operations using the /api/projects endpoint.

  This module validates that a request has proper authorization to access a project
  by calling the server's /api/projects endpoint and caching the results.
  """

  @failure_cache_ttl 3
  @success_cache_ttl 600
  @cache_name :cas_auth_cache

  require Logger

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@cache_name, []]}
    }
  end

  @doc """
  Ensures the request has access to the specified project.

  Returns `{:ok, auth_header}` if authorized, or `{:error, status, message}` otherwise.
  """
  def ensure_project_accessible(conn, account_handle, project_handle) do
    auth_header = Plug.Conn.get_req_header(conn, "authorization") |> List.first()

    Logger.info("Checking authorization for: #{account_handle}/#{project_handle} with auth header: #{auth_header}")

    if is_nil(auth_header) do
      {:error, 401, "Missing Authorization header"}
    else
      requested_handle = full_handle(account_handle, project_handle)

      case authorize(auth_header, requested_handle, conn) do
        :ok -> {:ok, auth_header}
        {:error, status, message} -> {:error, status, message}
      end
    end
  end

  defp authorize(auth_header, requested_handle, conn) do
    cache_key = generate_cache_key(auth_header)

    case cached_failure(cache_key) do
      {:error, status, message} ->
        {:error, status, message}

      :miss ->
        case evaluate_cached_project(cache_key, requested_handle) do
          :authorized ->
            :ok

          :unauthorized ->
            {:error, 404, "Unauthorized or not found"}

          :miss ->
            fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn)
        end
    end
  end

  defp cached_failure(cache_key) do
    case Cachex.get(@cache_name, {:failure, cache_key}) do
      {:ok, {status, message}} -> {:error, status, message}
      _ -> :miss
    end
  end

  defp evaluate_cached_project(cache_key, requested_handle) do
    case Cachex.get(@cache_name, {:primed, cache_key}) do
      {:ok, version} when is_integer(version) ->
        case Cachex.get(@cache_name, {cache_key, requested_handle}) do
          {:ok, {^version, :allowed}} -> :authorized
          {:ok, nil} -> :unauthorized
          _ -> :miss
        end

      _ ->
        :miss
    end
  end

  defp fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn) do
    headers = build_headers(auth_header, conn)
    options = request_options(headers)

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        prime_projects(cache_key, projects, requested_handle)

      {:ok, %{status: 403}} ->
        store_failure(cache_key, 404, "Unauthorized or not found")

      {:ok, %{status: 401}} ->
        store_failure(cache_key, 401, "Unauthorized")

      {:ok, %{status: status}} ->
        {:error, status, "Server responded with status #{status}"}

      {:error, reason} ->
        Logger.warning("Failed to fetch accessible projects: #{inspect(reason)}")
        {:error, 500, "Failed to fetch accessible projects"}
    end
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
    url = "#{base_url}/api/projects"

    req_options = Application.get_env(:cache, :req_options, [])

    Keyword.merge(
      [url: url, headers: headers, finch: Cache.Finch, retry: false, cache: false],
      req_options
    )
  end

  def server_url do
    case Application.get_env(:cache, :cas, []) do
      cas_config when is_list(cas_config) -> Keyword.get(cas_config, :server_url)
      _ -> nil
    end
  end

  defp success_ttl do
    :timer.seconds(@success_cache_ttl)
  end

  defp failure_ttl do
    :timer.seconds(@failure_cache_ttl)
  end

  def generate_cache_key(auth_header) do
    :crypto.hash(:sha256, auth_header)
    |> Base.encode16(case: :lower)
  end

  defp prime_projects(cache_key, projects, requested_handle) do
    version = System.unique_integer([:positive, :monotonic])
    ttl = success_ttl()

    {entries, authorized?} =
      Enum.reduce(projects, {[], false}, fn
        %{"full_name" => full_name}, {acc, allowed?} when is_binary(full_name) ->
          normalized = String.downcase(full_name)
          entry = {{cache_key, normalized}, {version, :allowed}}
          {[entry | acc], allowed? or normalized == requested_handle}

        _, acc ->
          acc
      end)

    {:ok, _} =
      Cachex.transaction(@cache_name, [cache_key], fn cache ->
        Cachex.put(cache, {:primed, cache_key}, version, ttl: ttl)
        Cachex.del(cache, {:failure, cache_key})

        case entries do
          [] -> :ok
          _ -> Cachex.put_many(cache, entries, ttl: ttl)
        end

        authorized?
      end)

    if authorized?, do: :ok, else: {:error, 404, "Unauthorized or not found"}
  end

  defp store_failure(cache_key, status, message) do
    ttl = failure_ttl()

    {:ok, _} =
      Cachex.transaction(@cache_name, [cache_key], fn cache ->
        Cachex.put(cache, {:failure, cache_key}, {status, message}, ttl: ttl)
        Cachex.del(cache, {:primed, cache_key})
      end)

    {:error, status, message}
  end

  defp full_handle(account_handle, project_handle) do
    "#{account_handle}/#{project_handle}"
    |> String.downcase()
  end
end
