defmodule Tuist.IngestRepo.Migrations.CreateReapiCacheInvocationSummariesMv do
  @moduledoc """
  Pre-aggregates REAPI cache events per invocation.

  The invocation list and the invocation detail page both need per-invocation
  cache totals, and both computed them by scanning raw `reapi_cache_events`
  on every request. A single invocation can record over 20,000 events - one
  per action-cache lookup and per blob transferred - so rendering one page of
  invocations scanned hundreds of thousands of rows to produce a handful of
  sums.

  Keyed by (project_id, invocation_id) because that is exactly how the
  summaries are looked up: callers already hold the invocation ids, having
  filtered the invocations themselves, so no environment or date predicate is
  needed on the events.

  BuildBuddy stores the equivalent totals denormalised on the invocation row
  (TotalDownloadSizeBytes, TotalDownloadUsec, DownloadThroughputBytesPerSecond)
  rather than deriving them per request.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS reapi_cache_invocation_summaries
    ENGINE = AggregatingMergeTree
    ORDER BY (project_id, invocation_id)
    POPULATE
    AS SELECT
      project_id,
      invocation_id,
      sumState(toUInt64(if(operation = 'action_cache' AND outcome = 'hit', 1, 0))) AS action_hits_state,
      sumState(toUInt64(if(operation = 'action_cache' AND outcome = 'miss', 1, 0))) AS action_misses_state,
      sumState(toUInt64(if(outcome = 'hit', size, 0))) AS download_bytes_state,
      sumState(toUInt64(if(outcome = 'write', size, 0))) AS upload_bytes_state,
      sumState(toUInt64(if(operation = 'cas' AND outcome = 'hit', size, 0))) AS content_download_bytes_state,
      sumState(toUInt64(if(operation = 'cas' AND outcome = 'write', size, 0))) AS content_upload_bytes_state,
      sumState(toUInt64(if(outcome = 'hit' AND size > 0 AND duration_us > 0, duration_us, 0))) AS download_duration_us_state,
      sumState(toUInt64(if(outcome = 'write' AND size > 0 AND duration_us > 0, duration_us, 0))) AS upload_duration_us_state
    FROM reapi_cache_events
    GROUP BY project_id, invocation_id
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP VIEW IF EXISTS reapi_cache_invocation_summaries")
  end
end
