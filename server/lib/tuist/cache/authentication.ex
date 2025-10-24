defmodule Tuist.Cache.Authentication do
  @moduledoc """
  Authentication for CAS operations using the /api/projects endpoint.

  This module validates that a request has proper authorization to access a project
  by calling the server's /api/projects endpoint and caching the results.
  """

  @failure_cache_ttl 300
  @success_cache_ttl 600
  @cache_name :cas_auth_cache

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

    if is_nil(auth_header) do
      {:error, 401, "Missing Authorization header"}
    else
      case get_accessible_projects(auth_header, conn) do
        {:ok, projects} ->
          requested_handle = "#{account_handle}/#{project_handle}"

          if project_accessible?(projects, requested_handle) do
            {:ok, auth_header}
          else
            {:error, 404, "Unauthorized or not found"}
          end

        {:error, status, message} ->
          {:error, status, message}
      end
    end
  end

  defp get_accessible_projects(auth_header, conn) do
    cache_key = generate_cache_key(auth_header)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        IO.puts("Authentication Cache: miss for #{cache_key}")
        fetch_and_cache_projects(auth_header, cache_key, conn)

      {:ok, cached_result} ->
        IO.puts("Authentication Cache: hit for #{cache_key}")
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

    cas_config = Application.get_env(:tuist, :cas, [])
    base_url = Keyword.get(cas_config, :server_url)
    url = "#{base_url}/api/projects"

    case Req.get(url: url, headers: headers, finch: Tuist.Finch, retry: false) do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        project_handles = Enum.map(projects, & &1["full_name"])
        result = {:ok, project_handles}

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

      {:error, _} ->
        {:error, 500, "Failed to fetch accessible projects"}
    end
  end

  defp generate_cache_key(auth_header) do
    :crypto.hash(:sha256, auth_header)
    |> Base.encode16(case: :lower)
  end

  defp project_accessible?(projects, requested_handle) do
    Enum.any?(projects, fn project ->
      String.downcase(project) == String.downcase(requested_handle)
    end)
  end
end
