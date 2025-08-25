defmodule Tuist.KeyValueStore do
  @moduledoc ~S"""
  A module for doing key-value caching. The storage layer depends on the presence of a Redis connection.
  - If a Redis connection is available, it caches the value in Redis.
  - If a Redis connection is not available, it caches the value in memory (cleaned in deploys)
  """

  alias Tuist.Environment

  @doc ~S"""
  This function returns a value from the cache using the given key and locking the access.
  If the key is accessed concurrently, the first caller will execute the function and cache the result,
  while the others suspend until the first caller completes.

  ## Opts

  - `:cache`: The cache to use. Defaults to `:tuist`.
  - `:ttl`: The time to live for the cached value. Defaults to `:timer.minutes(1)`.

  ## Examples

  iex> Tuist.KeyValueStore.get_or_update(:example_key, fn -> "example_value" end)
  "example_value"
  """
  def get_or_update(cache_key, opts \\ [], func) do
    if use_redis?(opts) do
      try do
        get_or_update_from_redis(cache_key, opts, func)
      rescue
        # With the current setup, we can't assume a valid Redis connection available,
        # therefore we need a fallback mechanism in those cases.
        error in Redix.ConnectionError ->
          Appsignal.set_error(error, __STACKTRACE__)
          get_or_update_from_cachex(cache_key, opts, func)
      end
    else
      get_or_update_from_cachex(cache_key, opts, func)
    end
  end

  defp get_or_update_from_redis(cache_key, opts, func) do
    cache_key = cache_key(cache_key)
    cache_ttl = Keyword.get(opts, :ttl, to_timeout(minute: 1))

    read_or_update = fn ->
      case Redix.command(Environment.redis_conn_name(), ["GET", cache_key]) do
        {:ok, nil} ->
          value = func.()

          Redix.command(Environment.redis_conn_name(), [
            "SET",
            cache_key,
            :erlang.term_to_binary(value),
            "EX",
            div(cache_ttl, 1000)
          ])

          value

        {:ok, value} ->
          :erlang.binary_to_term(value)
      end
    end

    if Keyword.get(opts, :locking, true) do
      RedisMutex.with_lock(
        "#{cache_key}-lock",
        read_or_update,
        name: Environment.redis_conn_name(),
        timeout: to_timeout(second: 5),
        expiry: to_timeout(second: 2)
      )
    else
      read_or_update.()
    end
  end

  defp get_or_update_from_cachex(cache_key, opts, func) do
    read_or_update = fn cache ->
      {:ok, cached_value} = Cachex.get(cache, cache_key(cache_key))

      case cached_value do
        nil ->
          value = func.()

          Cachex.put(cache, cache_key(cache_key), value, expire: cachex_cache_ttl(opts))

          value

        value ->
          value
      end
    end

    if Keyword.get(opts, :locking, true) do
      case Cachex.transaction(cachex_cache(opts), [cache_key(cache_key)], read_or_update) do
        {:ok, value} -> value
        # If the cache is unavailable, we handle it gracefully by obtaining the value without caching it.
        {:error, _reason} -> func.()
      end
    else
      read_or_update.(cachex_cache(opts))
    end
  end

  defp cachex_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  defp cachex_cache_ttl(opts) do
    Keyword.get(opts, :ttl, to_timeout(minute: 1))
  end

  defp cache_key(cache_key) do
    Enum.join(cache_key, "-")
  end

  defp use_redis?(opts) do
    Keyword.get(opts, :persist_across_deployments, false) and
      not is_nil(Environment.redis_url())
  end
end
