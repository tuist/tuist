defmodule TuistWeb.RateLimit.PersistentFixedWindow do
  @moduledoc false

  @behaviour Hammer

  alias Hammer.Redis.FixWindow
  alias TuistWeb.RateLimit.RedisPool

  @prefix "TuistWeb.RateLimit.PersistentFixedWindow"
  @timeout 500

  def child_spec(opts), do: RedisPool.child_spec(__MODULE__, opts)
  def start_link(opts), do: RedisPool.start_link(__MODULE__, opts)

  def hit(key, scale, limit, increment \\ 1) do
    FixWindow.hit(RedisPool.connection(__MODULE__), @prefix, key, scale, limit, increment, @timeout)
  end

  def inc(key, scale, increment \\ 1) do
    FixWindow.inc(RedisPool.connection(__MODULE__), @prefix, key, scale, increment, @timeout)
  end

  def set(key, scale, count) do
    FixWindow.set(RedisPool.connection(__MODULE__), @prefix, key, scale, count, @timeout)
  end

  def get(key, scale) do
    FixWindow.get(RedisPool.connection(__MODULE__), @prefix, key, scale, @timeout)
  end
end
