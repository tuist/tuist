defmodule Atlas.Licenses.RateLimiter.Buckets do
  @moduledoc """
  Pure fixed-window bucket algebra behind `Atlas.Licenses.RateLimiter`.

  Kept free of process and application environment state so the window,
  eviction, and retry-after behaviour that protects the public validation
  endpoint can be exercised directly with explicit clocks and limits.
  """

  @doc """
  An empty bucket store.

  A store maps an opaque identifier to `{attempts_so_far, window_started_at}`,
  where the timestamp is in monotonic milliseconds.
  """
  def new, do: %{}

  @doc """
  Records an attempt for `identifier` at `now` (monotonic milliseconds).

  Returns `{:ok, buckets}` while the identifier is under `:max_attempts` for the
  current window, and `{{:error, retry_after_seconds}, buckets}` once it is not,
  or when the store is already holding `:max_buckets` distinct identifiers.

  `limits` carries `:max_attempts`, `:window_milliseconds`, and `:max_buckets`.
  """
  def check(buckets, identifier, now, limits) when is_binary(identifier) do
    %{max_attempts: max_attempts, window_milliseconds: window, max_buckets: max_buckets} = limits
    buckets = prune(buckets, now, window)

    case Map.get(buckets, identifier) do
      nil when map_size(buckets) >= max_buckets ->
        {{:error, retry_after_seconds(window)}, buckets}

      nil ->
        {:ok, Map.put(buckets, identifier, {1, now})}

      {attempts, started_at} when attempts < max_attempts ->
        {:ok, Map.put(buckets, identifier, {attempts + 1, started_at})}

      {_attempts, started_at} ->
        remaining = max(window - (now - started_at), 1)
        {{:error, retry_after_seconds(remaining)}, buckets}
    end
  end

  @doc "Drops every bucket whose window has already elapsed at `now`."
  def prune(buckets, now, window_milliseconds) do
    Map.reject(buckets, fn {_identifier, {_attempts, started_at}} ->
      now - started_at >= window_milliseconds
    end)
  end

  defp retry_after_seconds(milliseconds), do: div(milliseconds + 999, 1000)
end
