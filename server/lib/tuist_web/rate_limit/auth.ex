defmodule TuistWeb.RateLimit.Auth do
  @moduledoc false

  alias TuistWeb.RateLimit

  def hit(conn) do
    key = "auth:#{TuistWeb.RemoteIp.get(conn)}"
    bucket_size = Tuist.Environment.auth_rate_limit_bucket_size()

    RateLimit.hit(
      key,
      algorithm: :token_bucket,
      refill_rate: 1 / 60,
      capacity: bucket_size
    )
  end
end
