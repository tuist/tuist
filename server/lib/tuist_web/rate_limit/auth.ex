defmodule TuistWeb.RateLimit.Auth do
  @moduledoc false
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  def hit(conn) do
    key = "auth:#{TuistWeb.RemoteIp.get(conn)}"
    bucket_size = Tuist.Environment.auth_rate_limit_bucket_size()

    if is_nil(Tuist.Environment.redis_url()) do
      InMemory.hit(key, to_timeout(minute: 1), bucket_size)
    else
      # 1 token per minute
      fill_rate = 1 / 60
      tokens_per_hit = 1
      PersistentTokenBucket.hit(key, fill_rate, bucket_size, tokens_per_hit)
    end
  end
end
