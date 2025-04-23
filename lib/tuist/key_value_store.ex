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

  iex> Tuist.KeyValueStore.get_value(:example_key, fn -> "example_value" end)
  "example_value"
  """

  def get_value(cache_key, opts \\ [], func) do
    if Keyword.get(opts, :persist_across_deployments, false) and
         not is_nil(Environment.redis_url()) do
      try do
        get_redis_value(cache_key, opts, func)
      rescue
        # With the current setup, we can't assume a valid Redis connection available,
        # therefore we need a fallback mechanism in those cases.
        error in Redix.ConnectionError ->
          Appsignal.set_error(error, __STACKTRACE__)
          get_cachex_value(cache_key, opts, func)
      end
    else
      get_cachex_value(cache_key, opts, func)
    end
  end

  defp get_redis_value(cache_key, opts \\ [], func) do
    cache_key = Enum.join(cache_key, "-")
    cache_ttl = Keyword.get(opts, :ttl, to_timeout(minute: 1))

    RedisMutex.with_lock(
      "#{cache_key}-lock",
      fn ->
        case Redix.command(:redis, ["GET", cache_key]) do
          {:ok, nil} ->
            value = func.()

            Redix.command(:redis, [
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
      end,
      name: :redis,
      timeout: to_timeout(second: 5),
      expiry: to_timeout(second: 2)
    )
  end

  defp get_cachex_value(cache_key, opts \\ [], func) do
    cache = Keyword.get(opts, :cache, :tuist)
    cache_ttl = Keyword.get(opts, :ttl, to_timeout(minute: 1))

    # Cachex.transaction! takes a list of keys, storing the same value under multiple keys.
    # However, since Cachex is setup to be distributed, only one key is allowed, so we allow
    # the caller of `get_value` to define the key as an array of keys (strings), which we then
    # turn into a single key by joining them with a hyphen.
    cache_key = [Enum.join(cache_key, "-")]

    Cachex.transaction!(cache, cache_key, fn cache ->
      {:ok, cached_value} = Cachex.get(cache, cache_key)

      case cached_value do
        nil ->
          value = func.()
          Cachex.put(cache, cache_key, value, ttl: cache_ttl)
          value

        value ->
          value
      end
    end)
  end
end
