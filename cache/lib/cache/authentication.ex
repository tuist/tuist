defmodule Cache.Authentication do
  @moduledoc """
  Authentication for CAS operations.

  This module validates that a request has proper authorization to access a project
  by first attempting to decode JWT tokens locally and extract the projects claim.
  For non-JWT tokens (e.g., project tokens), it falls back to calling the server's
  /api/projects endpoint and caching the results.
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
      {:ok, nil} -> authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn)
      {:ok, result} -> result
      _ -> authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn)
    end
  end

  defp authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn) do
    token = extract_token(auth_header)

    case verify_jwt(token, requested_handle) do
      {:ok, ttl} ->
        cache_result(cache_key, :ok, ttl)

      {:error, :not_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, conn)

      {:error, :project_not_in_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, conn)

      {:error, _reason} ->
        fetch_and_cache_projects(auth_header, cache_key, conn)
    end
  end

  defp extract_token("Bearer " <> token), do: token
  defp extract_token(token), do: token

  defp verify_jwt(token, requested_handle) do
    if Cache.Config.guardian_configured?() do
      do_verify_jwt(token, requested_handle)
    else
      {:error, :not_jwt}
    end
  end

  defp do_verify_jwt(token, requested_handle) do
    case Cache.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        verify_project_access(claims, requested_handle)

      {:error, _reason} ->
        {:error, :not_jwt}
    end
  end

  defp verify_project_access(claims, requested_handle) do
    projects = Map.get(claims, "projects", [])
    exp = Map.get(claims, "exp")

    if requested_handle in projects do
      {:ok, calculate_ttl(exp)}
    else
      {:error, :project_not_in_jwt}
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

  defp fetch_and_cache_projects(auth_header, cache_key, conn) do
    headers = build_headers(auth_header, conn)
    options = request_options(headers)

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"projects" => projects}}} ->
        cache_projects(cache_key, projects)

      {:ok, %{status: 403}} ->
        cache_result(cache_key, {:error, 403, "You don't have access to this project"}, failure_ttl())

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
        {:error, 403, "You don't have access to this project"}
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
