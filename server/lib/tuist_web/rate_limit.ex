defmodule TuistWeb.RateLimit do
  @moduledoc """
  Applies rate limits using Valkey with an in-memory fallback.

  Fixed-window limits use the `:limit` and `:window` options. Token-bucket
  limits use the `:capacity`, `:refill_rate`, and optional `:cost` options.
  """

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentFixedWindow
  alias TuistWeb.RateLimit.PersistentTokenBucket
  alias TuistWeb.RemoteIp

  def hit(key, opts) do
    algorithm = Keyword.get(opts, :algorithm, :fixed_window)

    if is_nil(Environment.redis_url()) do
      hit_in_memory(algorithm, key, opts)
    else
      hit_persistent(algorithm, key, opts)
    end
  end

  def rate_limit(%Plug.Conn{} = conn, opts) do
    if Environment.tuist_hosted?() do
      window = to_timeout(minute: 1)
      limit = opts[:limit] || Environment.dashboard_rate_limit_bucket_size()
      route = route_pattern(conn)
      key = "dashboard:#{conn.method}:#{route}:#{requester_key(conn)}"

      with :ok <- check(key, limit, window),
           :ok <- check_anon_scope(conn, window, opts) do
        conn
      else
        :deny ->
          raise TuistWeb.Errors.TooManyRequestsError,
            message: "You have made too many requests. Please try again later."
      end
    else
      conn
    end
  end

  defp check(key, limit, window) do
    case __MODULE__.hit(key, limit: limit, window: window) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> :deny
    end
  end

  # Aggregate anonymous traffic per (method, account[, project]) so a scraper
  # distributed across many residential-proxy IPs is caught even when no
  # single IP trips the per-subject key above. Signed-in requests are already
  # keyed by user and do not need this fallback.
  defp check_anon_scope(%Plug.Conn{} = conn, window, opts) do
    with nil <- Authentication.current_user(conn),
         scope when is_binary(scope) <- anon_scope(conn) do
      limit = opts[:anon_scope_limit] || Environment.public_project_rate_limit_bucket_size()
      check("dashboard:anon-scope:#{conn.method}:#{scope}", limit, window)
    else
      _ -> :ok
    end
  end

  defp anon_scope(%Plug.Conn{path_params: %{"account_handle" => account, "project_handle" => project}})
       when is_binary(account) and is_binary(project), do: "#{account}/#{project}"

  defp anon_scope(%Plug.Conn{path_params: %{"account_handle" => account}}) when is_binary(account), do: account

  defp anon_scope(_conn), do: nil

  defp hit_persistent(:fixed_window, key, opts) do
    window = Keyword.fetch!(opts, :window)
    limit = Keyword.fetch!(opts, :limit)
    increment = Keyword.get(opts, :increment, 1)

    with_in_memory_fallback(
      fn -> PersistentFixedWindow.hit(key, window, limit, increment) end,
      fn -> InMemory.hit(key, window, limit, increment) end
    )
  end

  defp hit_persistent(:token_bucket, key, opts) do
    refill_rate = Keyword.fetch!(opts, :refill_rate)
    capacity = Keyword.fetch!(opts, :capacity)
    cost = Keyword.get(opts, :cost, 1)

    with_in_memory_fallback(
      fn -> PersistentTokenBucket.hit(key, refill_rate, capacity, cost) end,
      fn -> InMemory.hit_token_bucket(key, refill_rate, capacity, cost) end
    )
  end

  defp hit_in_memory(:fixed_window, key, opts) do
    InMemory.hit(
      key,
      Keyword.fetch!(opts, :window),
      Keyword.fetch!(opts, :limit),
      Keyword.get(opts, :increment, 1)
    )
  end

  defp hit_in_memory(:token_bucket, key, opts) do
    InMemory.hit_token_bucket(
      key,
      Keyword.fetch!(opts, :refill_rate),
      Keyword.fetch!(opts, :capacity),
      Keyword.get(opts, :cost, 1)
    )
  end

  defp with_in_memory_fallback(persistent, in_memory) do
    persistent.()
  rescue
    _error in [MatchError, Redix.ConnectionError, Redix.Error] -> in_memory.()
  catch
    :exit, _reason -> in_memory.()
  end

  defp requester_key(conn) do
    case Authentication.current_user(conn) do
      %{id: id} -> "user:#{id}"
      nil -> "ip:#{RemoteIp.get(conn)}"
    end
  end

  defp route_pattern(conn) do
    case conn.private[:phoenix_router] do
      nil ->
        conn.request_path

      router ->
        case Phoenix.Router.route_info(router, conn.method, conn.path_info, conn.host) do
          %{route: route} -> route
          :error -> conn.request_path
        end
    end
  end
end
