defmodule TuistWeb.RateLimit.Metrics do
  @moduledoc """
  Rate limiter for the per-account `/metrics` scrape endpoint.

  The ceiling is roughly one scrape per ten seconds. A modest burst is allowed
  so agents that jitter their scrape schedule don't fail on the first request
  after startup.
  """
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  @bucket_size 3
  @fill_rate 0.1
  @tokens_per_hit 1

  @doc """
  Records a hit for an account and returns `{:allow, count}` or
  `{:deny, limit}`.
  """
  def hit(account_id) do
    key = "metrics:#{account_id}"

    if is_nil(Tuist.Environment.redis_url()) do
      # Without a shared Redis this is a best-effort per-node limit — the
      # In-Memory listener broadcasts increments so it converges quickly.
      InMemory.hit(key, to_timeout(second: 30), @bucket_size)
    else
      PersistentTokenBucket.hit(key, @fill_rate, @bucket_size, @tokens_per_hit)
    end
  end
end
