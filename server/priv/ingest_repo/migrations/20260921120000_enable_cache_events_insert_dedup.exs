defmodule Tuist.IngestRepo.Migrations.EnableCacheEventsInsertDedup do
  @moduledoc """
  Enable ClickHouse INSERT-level deduplication on the three cache analytics
  tables (`gradle_cache_events`, `cas_events`, `reapi_cache_events`).

  The server now attaches an `insert_deduplication_token` derived from the
  producer's `event_id` batch fingerprint on every insert (see
  `Tuist.Ingestion.DedupToken`). ClickHouse only honours that token when
  the table remembers a non-zero window of recent tokens:

    - `non_replicated_deduplication_window` for plain `MergeTree` (the
      shape on-premise customers get when they self-host a single node).
      Default is 0, which silently ignores the token.
    - `replicated_deduplication_window` for `ReplicatedMergeTree` and its
      shared/managed variants. Default is already 1000 there.

  Setting both unconditionally lets the same migration work on managed
  (Shared/Replicated, where the non-replicated setting is a no-op) and on
  self-hosted single-node MergeTree, matching the pattern established for
  `automation_alert_events` and `test_case_runs_by_commit`.

  1000 covers roughly the last 1000 tokens per partition, which is far
  more than any retried batch of Kura's analytics client would need to
  span. The setting is metadata-only and applies immediately.
  """

  use Ecto.Migration

  @window 1000
  @tables ["gradle_cache_events", "cas_events", "reapi_cache_events"]

  def up do
    for table <- @tables do
      execute("""
      ALTER TABLE #{table}
      MODIFY SETTING
        non_replicated_deduplication_window = #{@window},
        replicated_deduplication_window = #{@window}
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("""
      ALTER TABLE #{table}
      MODIFY SETTING
        non_replicated_deduplication_window = 0,
        replicated_deduplication_window = 0
      """)
    end
  end
end
