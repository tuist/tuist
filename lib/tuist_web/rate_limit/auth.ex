defmodule TuistWeb.RateLimit.Auth do
  @moduledoc false
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  def hit(conn) do
    key = "auth:#{TuistWeb.RemoteIp.get(conn)}"

    if is_nil(Tuist.Environment.redis_url()) do
      InMemory.hit(key, to_timeout(minute: 1), 10)
    else
      # 1 token per minute
      fill_rate = 1 / 60
      bucket_size = 10
      tokens_per_hit = 1
      PersistentTokenBucket.hit(key, fill_rate, bucket_size, tokens_per_hit)
    end
  end
end
