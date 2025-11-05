defmodule Cache.Authentication do
  @moduledoc """
  Authentication for CAS operations using the /api/projects endpoint.

  This module validates that a request has proper authorization to access a project
  by calling the server's /api/projects endpoint and caching the results.
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
  def ensure_project_accessible(conn, account_handle, project_handle) do
    auth_header = conn |> Plug.Conn.get_req_header("authorization") |> List.first()

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
    cache_key = {generate_cache_key(auth_header), requested_handle}

    case Cachex.get(cache_name(), cache_key) do
      {:ok, nil} -> fetch_and_cache_projects(auth_header, cache_key, conn)
      {:ok, result} -> result
      _ -> fetch_and_cache_projects(auth_header, cache_key, conn)
    end
  end

  defp fetch_and_cache_projects(auth_header, cache_key, conn) do
    headers = build_headers(auth_header, conn)
    options = request_options(headers)

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        cache_projects(cache_key, projects)

      {:ok, %{status: 403}} ->
        cache_result(cache_key, {:error, 404, "Unauthorized or not found"}, failure_ttl())

      {:ok, %{status: 401}} ->
        cache_result(cache_key, {:error, 401, "Unauthorized"}, failure_ttl())

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

  defp cache_projects({auth_key, requested_handle}, projects) do
    ttl = success_ttl()

    project_handles =
      projects
      |> Enum.map(fn
        %{"full_name" => name} when is_binary(name) -> String.downcase(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    result =
      if MapSet.member?(project_handles, requested_handle) do
        :ok
      else
        {:error, 404, "Unauthorized or not found"}
      end

    cache_result({auth_key, requested_handle}, result, ttl)
  end

  defp cache_result(cache_key, result, ttl) do
    Cachex.put(cache_name(), cache_key, result, ttl: ttl)
    result
  end

  defp full_handle(account_handle, project_handle) do
    String.downcase("#{account_handle}/#{project_handle}")
  end
end
