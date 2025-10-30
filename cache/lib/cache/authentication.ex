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
      case get_accessible_projects(auth_header, conn) do
        {:ok, project_set} ->
          requested_handle = String.downcase("#{account_handle}/#{project_handle}")

          if MapSet.member?(project_set, requested_handle) do
            {:ok, auth_header}
          else
            {:error, 404, "Unauthorized or not found"}
          end

        {:error, status, message} ->
          {:error, status, message}
      end
    end
  end

  @doc """
  Ensures access using project context provided via request headers.

  Expected headers (lowercased by Plug):
  - "x-account-handle"
  - "x-project-handle"

  Returns `{:ok, auth_header}` if authorized, or `{:error, status, message}`.
  Returns `{:error, 400, _}` if headers are missing.
  """
  def ensure_project_accessible_from_headers(conn) do
    with [account_handle] <- Plug.Conn.get_req_header(conn, "x-account-handle"),
         [project_handle] <- Plug.Conn.get_req_header(conn, "x-project-handle") do
      auth_header = Plug.Conn.get_req_header(conn, "authorization") |> List.first()

      Logger.debug(
        "AUTH_CAS: Ensuring project #{project_handle} is accessible from account #{account_handle} with header #{auth_header}"
      )

      ensure_project_accessible(conn, account_handle, project_handle)
    else
      _ -> {:error, 400, "Missing account/project headers"}
    end
  end

  defp get_accessible_projects(auth_header, conn) do
    cache_key = generate_cache_key(auth_header)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        fetch_and_cache_projects(auth_header, cache_key, conn)

      {:ok, cached_result} ->
        cached_result

      _ ->
        fetch_and_cache_projects(auth_header, cache_key, conn)
    end
  end

  defp fetch_and_cache_projects(auth_header, cache_key, conn) do
    headers = [{"authorization", auth_header}]

    headers =
      case Plug.Conn.get_req_header(conn, "x-request-id") do
        [request_id | _] -> [{"x-request-id", request_id} | headers]
        _ -> headers
      end

    cas_config = Application.get_env(:cache, :cas, [])
    base_url = Keyword.get(cas_config, :server_url)
    url = "#{base_url}/api/projects"

    case Req.get(url: url, headers: headers, finch: Cache.Finch, retry: false) do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        # Pre-lowercase project handles and convert to MapSet for O(1) lookup
        project_set =
          projects
          |> Enum.map(&String.downcase(&1["full_name"]))
          |> MapSet.new()

        result = {:ok, project_set}

        Cachex.put(@cache_name, cache_key, result, ttl: :timer.seconds(@success_cache_ttl))
        result

      {:ok, %{status: 403}} ->
        result = {:error, 404, "Unauthorized or not found"}
        Cachex.put(@cache_name, cache_key, result, ttl: :timer.seconds(@failure_cache_ttl))
        result

      {:ok, %{status: 401}} ->
        result = {:error, 401, "Unauthorized"}
        Cachex.put(@cache_name, cache_key, result, ttl: :timer.seconds(@failure_cache_ttl))
        result

      {:ok, %{status: status}} ->
        {:error, status, "Server responded with status #{status}"}

      {:error, _error} ->
        {:error, 500, "Failed to fetch accessible projects"}
    end
  end

  defp generate_cache_key(auth_header) do
    :crypto.hash(:sha256, auth_header)
    |> Base.encode16(case: :lower)
  end
end
