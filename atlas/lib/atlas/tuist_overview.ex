defmodule Atlas.TuistOverview do
  @moduledoc """
  High-level counts pulled from the Tuist server for the Atlas overview page.

  Each stat is queried through `Atlas.TuistServer`'s read-only Postgres and
  ClickHouse proxies, so Atlas never talks to the Tuist databases directly.
  Postgres-backed rollups (users, organizations, projects, jobs) are total
  counts; the cache-operation count is windowed to the last 30 days because the
  ClickHouse event tables grow without bound.
  """

  alias Atlas.Environment
  alias Atlas.TuistServer

  require Logger

  @cache_events_window_days 30

  # Illustrative counts shown in dev when the Tuist server is not reachable
  # (the projected SA token file only exists in-cluster), so operators can see
  # the overview page rendered with real numbers while iterating.
  @dev_sample_stats %{
    users: 12_483,
    organizations: 947,
    projects: 6_128,
    jobs: 84_502,
    cache_operations: 42_378_915
  }

  @doc """
  Fetches every overview stat. Returns a map with `{:ok, integer}` or
  `{:error, term}` per key, so a single failing query never blanks the whole
  page. When the Tuist server is not configured for this environment (dev /
  test) every stat is `{:error, :not_configured}`.
  """
  def stats(opts \\ []) do
    pg_query = Keyword.get(opts, :pg_query, &TuistServer.query/2)
    ch_query = Keyword.get(opts, :ch_query, &TuistServer.clickhouse_query/2)
    configured_fun = Keyword.get(opts, :configured?, &TuistServer.configured?/0)

    cond do
      configured_fun.() ->
        %{
          users: count_postgres(pg_query, "SELECT count(*) AS c FROM users"),
          organizations: count_postgres(pg_query, "SELECT count(*) AS c FROM organizations"),
          projects: count_postgres(pg_query, "SELECT count(*) AS c FROM projects"),
          jobs: count_postgres(pg_query, "SELECT count(*) AS c FROM runner_jobs"),
          cache_operations: cache_operations(ch_query)
        }

      Environment.dev?() ->
        Map.new(@dev_sample_stats, fn {key, value} -> {key, {:ok, value}} end)

      true ->
        Map.new([:users, :organizations, :projects, :jobs, :cache_operations], &{&1, {:error, :not_configured}})
    end
  end

  @doc "Number of days the cache-operation stat covers."
  def cache_operations_window_days, do: @cache_events_window_days

  defp count_postgres(pg_query, sql) do
    case pg_query.(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} -> {:ok, extract_count(row)}
      {:ok, %{"rows" => []}} -> {:ok, 0}
      {:error, reason} -> log_and_error("Tuist overview Postgres query failed", reason)
    end
  end

  # Sums the three ClickHouse cache-event tables in one round trip. `SETTINGS`
  # is not supported by the read-only proxy grammar, so the window bound is
  # inlined; the value is a compile-time constant so no user input is
  # interpolated.
  defp cache_operations(ch_query) do
    sql = """
    SELECT
      (SELECT count() FROM cache_events WHERE created_at >= now() - INTERVAL #{@cache_events_window_days} DAY) +
      (SELECT count() FROM reapi_cache_events WHERE created_at >= now() - INTERVAL #{@cache_events_window_days} DAY) +
      (SELECT count() FROM gradle_cache_events WHERE created_at >= now() - INTERVAL #{@cache_events_window_days} DAY)
      AS c
    """

    case ch_query.(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} -> {:ok, extract_count(row)}
      {:ok, %{"rows" => []}} -> {:ok, 0}
      {:error, reason} -> log_and_error("Tuist overview ClickHouse query failed", reason)
    end
  end

  defp extract_count(row) do
    row
    |> Map.get("c", 0)
    |> to_integer()
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> 0
    end
  end

  defp to_integer(_value), do: 0

  defp log_and_error(prefix, reason) do
    Logger.warning("#{prefix}: #{inspect(reason)}")
    {:error, reason}
  end
end
