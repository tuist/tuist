defmodule Tuist.RateLimit do
  @moduledoc """
  Shared rate limits for domain operations and web requests. Configured Valkey
  failures deny by default; explicitly selected fixed-window callers may use a
  reduced node-local outage budget. Without Valkey, admission is approximate.
  """

  alias Tuist.Environment
  alias Tuist.RateLimit.InMemory
  alias Tuist.RateLimit.PersistentFixedWindow
  alias Tuist.RateLimit.PersistentTokenBucket

  def hit(key, opts) do
    algorithm = Keyword.get(opts, :algorithm, :fixed_window)

    if is_nil(Environment.redis_url()) do
      hit_in_memory(algorithm, key, opts)
    else
      hit_persistent(algorithm, key, opts)
    end
  end

  defp hit_persistent(:fixed_window, key, opts) do
    window = Keyword.fetch!(opts, :window)
    limit = Keyword.fetch!(opts, :limit)
    increment = Keyword.get(opts, :increment, 1)

    with_failure_denial(
      fn -> PersistentFixedWindow.hit(key, window, limit, increment) end,
      fn -> fixed_window_failure(key, opts, window) end
    )
  end

  defp hit_persistent(:token_bucket, key, opts) do
    refill_rate = Keyword.fetch!(opts, :refill_rate)
    capacity = Keyword.fetch!(opts, :capacity)
    cost = Keyword.get(opts, :cost, 1)

    with_failure_denial(
      fn -> PersistentTokenBucket.hit(key, refill_rate, capacity, cost) end,
      fn ->
        shared_failure(:token_bucket, :deny, fn ->
          if opts[:fallback] == false,
            do: {:error, :unavailable},
            else: {:deny, ceil(cost / refill_rate * 1000)}
        end)
      end
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

  defp with_failure_denial(persistent, fallback) do
    result =
      try do
        persistent.()
      rescue
        _error in [MatchError, Redix.ConnectionError, Redix.Error] -> :unavailable
      catch
        :exit, _reason -> :unavailable
      end

    case result do
      {:allow, count} when is_integer(count) and count >= 0 -> result
      {:deny, retry_after} when is_integer(retry_after) and retry_after >= 0 -> result
      _other -> fallback.()
    end
  end

  defp fixed_window_failure(key, opts, window) do
    policy =
      if opts[:failure_policy] == :local and opts[:fallback] != false, do: :local, else: :deny

    shared_failure(:fixed_window, policy, fn ->
      cond do
        opts[:fallback] == false -> {:error, :unavailable}
        policy == :local -> hit_local(key, opts, window)
        true -> {:deny, window}
      end
    end)
  end

  defp hit_local(key, opts, window) do
    configured = Environment.rate_limit_fallback_replicas()

    if is_integer(configured) and configured >= 5 do
      replicas = max(configured, length(Node.list()) + 1)
      budget = div(Keyword.fetch!(opts, :limit), replicas)

      if budget > 0 do
        InMemory.Local.hit({:fallback, key}, window, budget, Keyword.get(opts, :increment, 1))
      else
        {:deny, window}
      end
    else
      {:deny, window}
    end
  rescue
    ArgumentError -> {:deny, window}
  catch
    :exit, _reason -> {:deny, window}
  end

  defp shared_failure(algorithm, policy, fallback) do
    {outcome, _value} = result = fallback.()

    :telemetry.execute([:tuist, :rate_limit, :shared_failure], %{count: 1}, %{
      algorithm: algorithm,
      policy: policy,
      outcome: outcome
    })

    result
  end
end
