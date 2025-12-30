defmodule TuistWeb.RateLimit.PersistentTokenBucket do
  @moduledoc ~S"""
  This module provides an interface for rate-limit that persisted across deployments and uses the [token bucket](https://github.com/ExHammer/hammer-backend-redis/blob/master/lib/hammer/redis/token_bucket.ex) algorithm.

  With this algorithm the bucket is filled at a certain rate, and once it's filled, no more hits are allowed. Note that the
  cleaning of old hits doesn't happened based on the option :clean_period as stated in the docs. The Redis LUA script
  of the backend is configured such that the expiration time is determined dynamically based on how long it would take for the
  token bucket to refill completely, plus a 60-second buffer.
  """
  use Hammer, backend: Hammer.Redis, timeout: :infinity, algorithm: :token_bucket
end
