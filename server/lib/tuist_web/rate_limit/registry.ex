defmodule TuistWeb.RateLimit.Registry do
  @moduledoc """
  Rate limiting for registry endpoints, particularly for unauthenticated access.
  """
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  def hit(conn) do
    key = "registry:#{TuistWeb.RemoteIp.get(conn)}"
    bucket_size = 1000

    if is_nil(Tuist.Environment.redis_url()) do
      # 1000 requests per minute for in-memory
      InMemory.hit(key, to_timeout(minute: 1), bucket_size)
    else
      # Token bucket: 1 token per second (60 per minute)
      fill_rate = 1 / 1
      tokens_per_hit = 1
      PersistentTokenBucket.hit(key, fill_rate, bucket_size, tokens_per_hit)
    end
  end
end
