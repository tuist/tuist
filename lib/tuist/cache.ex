defmodule Tuist.Cache do
  @moduledoc ~S"""
  A module that adds a convenience layer to Cachex.
  """

  @doc ~S"""
  This function returns a value from the cache using the given key and locking the access.
  If the key is accessed concurrently, the first caller will execute the function and cache the result,
  while the others suspend until the first caller completes.

  ## Opts

  - `:cache`: The cache to use. Defaults to `:tuist`.
  - `:ttl`: The time to live for the cached value. Defaults to `:timer.minutes(1)`.

  ## Examples

  iex> Tuist.Cache.get_value(:example_key, fn -> "example_value" end)
  "example_value"
  """
  def get_value(cache_key, opts \\ [], func) do
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
