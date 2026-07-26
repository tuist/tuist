defmodule Tuist.KeyValueStore do
  @moduledoc ~S"""
  A module for doing key-value caching. The storage layer depends on the presence of a Redis connection.
  - If a Redis connection is available, it caches the value in Redis.
  - If a Redis connection is not available, it caches the value in memory (cleaned in deploys)
  """

  alias Tuist.Environment

  @doc ~S"""
  This function returns a value from the cache using the given key without updating it.
  Returns `nil` if the key is not found.

  ## Opts

  - `:cache`: The cache to use. Defaults to `:tuist`.

  ## Examples

  iex> Tuist.KeyValueStore.get(:example_key)
  nil
  """
  def get(cache_key, opts \\ []) do
    if use_redis?(opts) do
      try do
        get_from_redis(cache_key)
      rescue
        _error in Redix.ConnectionError ->
          get_from_cachex(cache_key, opts)
      end
    else
      get_from_cachex(cache_key, opts)
    end
  end

  @doc ~S"""
  Stores a value in the cache using the given key.

  ## Opts

  - `:cache`: The cache to use. Defaults to `:tuist`.
  - `:ttl`: The time to live for the cached value. Defaults to `:timer.minutes(1)`.

  ## Examples

  iex> Tuist.KeyValueStore.put(:example_key, "example_value")
  {:ok, true}
  """
  def put(cache_key, value, opts \\ []) do
    if use_redis?(opts) do
      try do
        put_in_redis(cache_key, value, opts)
      rescue
        _error in Redix.ConnectionError ->
          put_in_cachex(cache_key, value, opts)
      end
    else
      put_in_cachex(cache_key, value, opts)
    end
  end

  defp get_from_redis(cache_key) do
    case Redix.command(Environment.redis_conn_name(), ["GET", cache_key(cache_key)]) do
      {:ok, nil} ->
        nil

      {:ok, value} ->
        case deserialize(value) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  defp get_from_cachex(cache_key, opts) do
    read_from_cachex(cachex_cache(opts), cache_key(cache_key))
  end

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
          Sentry.capture_exception(error, stacktrace: __STACKTRACE__)
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
          case deserialize(value) do
            :error ->
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
              value
          end
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
    cache_key = cache_key(cache_key)

    read_or_update = fn cache ->
      case read_from_cachex(cache, cache_key) do
        nil ->
          value = func.()

          Cachex.put(cache, cache_key, value, expire: cachex_cache_ttl(opts))

          value

        value ->
          value
      end
    end

    if Keyword.get(opts, :locking, true) do
      run_cachex_transaction(cachex_cache(opts), [cache_key], read_or_update, func)
    else
      read_or_update.(cachex_cache(opts))
    end
  end

  defp put_in_redis(cache_key, value, opts) do
    cache_key = cache_key(cache_key)
    cache_ttl = Keyword.get(opts, :ttl, to_timeout(minute: 1))

    Redix.command(Environment.redis_conn_name(), [
      "SET",
      cache_key,
      :erlang.term_to_binary(value),
      "EX",
      div(cache_ttl, 1000)
    ])
  end

  defp put_in_cachex(cache_key, value, opts) do
    opts
    |> cachex_cache()
    |> Cachex.put(cache_key(cache_key), value, expire: cachex_cache_ttl(opts))
    |> normalize_cachex_put()
  end

  defp read_from_cachex(cache, cache_key) do
    cache
    |> Cachex.get(cache_key)
    |> normalize_cachex_get()
  rescue
    _error in ArgumentError -> nil
  end

  defp normalize_cachex_get({:ok, cached_value}) do
    if cachex_returns_wrapped_results?(), do: cached_value, else: {:ok, cached_value}
  end

  defp normalize_cachex_get({:error, reason}) do
    if cachex_returns_wrapped_results?(), do: nil, else: {:error, reason}
  end

  defp normalize_cachex_get(cached_value), do: cached_value

  defp normalize_cachex_put(:ok), do: {:ok, true}
  defp normalize_cachex_put(result), do: result

  defp run_cachex_transaction(cache, keys, operation, fallback) do
    result = Cachex.transaction(cache, keys, operation)

    if cachex_returns_wrapped_results?() do
      case result do
        {:ok, value} -> value
        # If the cache is unavailable, we handle it gracefully by obtaining the value without caching it.
        {:error, _reason} -> fallback.()
        value -> value
      end
    else
      result
    end
  rescue
    _error in ArgumentError -> fallback.()
  end

  defp cachex_returns_wrapped_results? do
    case Application.spec(:cachex, :vsn) do
      nil -> false
      version -> Version.match?(List.to_string(version), "< 4.1.0")
    end
  end

  defp cachex_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  defp cachex_cache_ttl(opts) do
    Keyword.get(opts, :ttl, to_timeout(minute: 1))
  end

  defp cache_key(cache_key) when is_list(cache_key), do: Enum.map_join(cache_key, "-", &to_string/1)
  defp cache_key(cache_key) when is_atom(cache_key), do: Atom.to_string(cache_key)
  defp cache_key(cache_key) when is_binary(cache_key), do: cache_key

  defp deserialize(value) do
    {:ok, :erlang.binary_to_term(value, [:safe])}
  rescue
    _error in ArgumentError -> :error
  end

  defp use_redis?(opts) do
    Keyword.get(opts, :persist_across_deployments, false) and
      not is_nil(Environment.redis_url())
  end
end
