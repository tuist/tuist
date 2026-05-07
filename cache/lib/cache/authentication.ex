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

  Returns `{:ok, auth_header, billing}` if authorized, where `billing` is either
  the billing snapshot for the account (a map with `:plan`,
  `:subscription_active`, `:thresholds_surpassed`) or `nil` when it could not
  be determined locally (e.g. JWT-only authorization). Returns
  `{:error, status, message}` otherwise.
  """
  def ensure_project_accessible(conn, account_handle, project_handle, opts \\ []) do
    auth_header = conn |> Plug.Conn.get_req_header("authorization") |> List.first()
    cache = Keyword.get(opts, :cache_name, cache_name())

    if is_nil(auth_header) do
      {:error, 401, "Missing Authorization header"}
    else
      requested_handle = full_handle(account_handle, project_handle)

      case authorize(auth_header, requested_handle, conn, cache) do
        {:ok, billing} ->
          {:ok, auth_header, billing}

        {:error, status, message} ->
          {:error, status, message}
      end
    end
  end

  defp authorize(auth_header, requested_handle, conn, cache) do
    cache_key = {generate_cache_key(auth_header), requested_handle}

    case Cachex.get(cache, cache_key) do
      {:ok, nil} ->
        :telemetry.execute([:cache, :auth, :cache, :miss], %{}, %{})
        authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache)

      {:ok, result} ->
        :telemetry.execute([:cache, :auth, :cache, :hit], %{}, %{})
        if match?({:ok, _}, result), do: :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :cache})
        result

      _ ->
        :telemetry.execute([:cache, :auth, :cache, :miss], %{}, %{})
        authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache)
    end
  end

  defp authorize_with_jwt_or_api(auth_header, cache_key, requested_handle, conn, cache) do
    token = extract_token(auth_header)

    case verify_jwt(token, requested_handle) do
      {:ok, ttl} ->
        :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :jwt})
        cache_result(cache, cache_key, {:ok, nil}, ttl)

      {:error, :not_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn, cache)

      {:error, :project_not_in_jwt} ->
        fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn, cache)

      {:error, _reason} ->
        fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn, cache)
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

  defp fetch_and_cache_projects(auth_header, cache_key, requested_handle, conn, cache) do
    headers = build_headers(auth_header, conn)
    options = request_options(headers)

    cache
    |> Cachex.fetch(cache_key, fn -> fetch_projects(cache_key, requested_handle, options) end)
    |> unwrap_fetch_result()
  end

  defp fetch_projects(cache_key, requested_handle, options) do
    start_time = System.monotonic_time()
    :telemetry.execute([:cache, :auth, :server, :request], %{}, %{})

    result = Req.get(options)

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:cache, :auth, :server, :response], %{duration: duration}, %{})

    case result do
      {:ok, %{status: 200, body: %{"projects" => projects} = body}} ->
        result = project_access_result(cache_key, projects, Map.get(body, "accounts", []), requested_handle)
        ttl = if match?({:ok, _}, result), do: success_ttl(), else: failure_ttl()
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
    url = "#{base_url}/api/projects"

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

  defp project_access_result({_auth_key, _requested_handle}, projects, accounts, requested_handle) do
    project_handles =
      projects
      |> Enum.map(fn
        %{"full_name" => name} when is_binary(name) -> String.downcase(name)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.member?(project_handles, requested_handle) do
      :telemetry.execute([:cache, :auth, :authorized], %{}, %{method: :server})
      {:ok, billing_for_handle(accounts, requested_handle)}
    else
      {:error, 403, "You don't have access to this project"}
    end
  end

  defp billing_for_handle(accounts, requested_handle) when is_list(accounts) do
    [account_handle, _project_handle] = String.split(requested_handle, "/", parts: 2)

    Enum.find_value(accounts, fn
      %{"name" => name} = account when is_binary(name) ->
        if String.downcase(name) == account_handle, do: parse_billing(account)

      _ ->
        nil
    end)
  end

  defp billing_for_handle(_accounts, _requested_handle), do: nil

  defp parse_billing(%{
         "plan" => plan,
         "subscription_active" => subscription_active,
         "thresholds_surpassed" => thresholds_surpassed
       })
       when is_binary(plan) do
    %{
      plan: parse_plan(plan),
      subscription_active: subscription_active == true,
      thresholds_surpassed: thresholds_surpassed == true
    }
  end

  defp parse_billing(_), do: nil

  defp parse_plan("air"), do: :air
  defp parse_plan("pro"), do: :pro
  defp parse_plan("open_source"), do: :open_source
  defp parse_plan("enterprise"), do: :enterprise
  defp parse_plan(_), do: :unknown

  defp cache_result(cache, cache_key, result, ttl) do
    Cachex.put(cache, cache_key, result, ttl: ttl)
    result
  end

  defp full_handle(account_handle, project_handle) do
    String.downcase("#{account_handle}/#{project_handle}")
  end
end
