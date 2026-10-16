defmodule TuistWeb.RateLimit.PersistentTokenBucket do
  @moduledoc false

  @behaviour Hammer

  alias Hammer.Redis.TokenBucket
  alias TuistWeb.RateLimit.RedisPool

  @prefix "TuistWeb.RateLimit.PersistentTokenBucket"
  @timeout 500

  def child_spec(opts), do: RedisPool.child_spec(__MODULE__, opts)
  def start_link(opts), do: RedisPool.start_link(__MODULE__, opts)

  def hit(key, refill_rate, capacity, cost \\ 1) do
    TokenBucket.hit(RedisPool.connection(__MODULE__), @prefix, key, refill_rate, capacity, cost, @timeout)
  end

  def get(key) do
    TokenBucket.get(RedisPool.connection(__MODULE__), @prefix, key, @timeout)
  end
end
