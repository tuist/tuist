defmodule Atlas.RateLimit do
  @moduledoc """
  Shared fixed-window rate limits backed by PostgreSQL.

  An atomic upsert serializes attempts for the same hashed key across replicas.
  PostgreSQL supplies the clock, and denied attempts neither extend a window nor
  overflow its counter. Raw client addresses and credentials are never stored.
  Expired buckets are pruned by `Atlas.Workers.PruneRateLimits`.
  """

  alias Atlas.Repo

  def hit(key, window_milliseconds, limit)
      when is_binary(key) and is_integer(window_milliseconds) and window_milliseconds > 0 and is_integer(limit) and
             limit > 0 do
    key_hash = :crypto.hash(:sha256, "#{window_milliseconds}:#{key}")

    sql = """
    INSERT INTO rate_limit_buckets AS bucket (key_hash, attempts, expires_at)
    VALUES ($1, 1, statement_timestamp() + $2 * interval '1 millisecond')
    ON CONFLICT (key_hash) DO UPDATE SET
      attempts = CASE WHEN bucket.expires_at <= statement_timestamp() THEN 1
                      ELSE LEAST(bucket.attempts + 1, $3 + 1) END,
      expires_at = CASE WHEN bucket.expires_at <= statement_timestamp()
                        THEN EXCLUDED.expires_at ELSE bucket.expires_at END
    RETURNING attempts,
      GREATEST(1, ceil(extract(epoch FROM (expires_at - statement_timestamp())) * 1000))::bigint
    """

    case Repo.query(sql, [key_hash, window_milliseconds, limit]) do
      {:ok, %{rows: [[attempts, _remaining]]}} when attempts <= limit -> {:allow, attempts}
      {:ok, %{rows: [[_attempts, remaining]]}} -> {:deny, remaining}
      # Public mail and credential validation must fail closed when the shared
      # limiter is unavailable, not silently fall back to per-node counters.
      {:error, _reason} -> {:deny, window_milliseconds}
    end
  end

  def prune_expired do
    Repo.query!("DELETE FROM rate_limit_buckets WHERE expires_at <= statement_timestamp()")
    :ok
  end
end
