defmodule Tuist.IngestRepo.Migrations.CreateWebhookDeliveryAttemptsTable do
  use Ecto.Migration

  # `webhook_delivery_attempts` is an append-only audit log for every
  # outbound HTTP attempt produced by `Tuist.Webhooks.Workers.DeliveryWorker`.
  # One row per attempt; the row is never updated after the worker writes
  # it. Powers the per-endpoint deliveries chart and the per-event detail
  # page on the dashboard.
  #
  # MergeTree (not ReplacingMergeTree) — rows are immutable, so there's
  # nothing to deduplicate by version.
  #
  # ORDER BY (webhook_endpoint_id, inserted_at) is the primary read path:
  # "deliveries for this endpoint in this time window" with optional
  # status / event-type / event-id filters. Putting the endpoint id first
  # gives the queries good partition pruning + range scans inside each
  # part.
  #
  # PARTITION BY toYYYYMM(inserted_at) matches every other CH table in
  # this codebase and pairs with the TTL clause.
  #
  # TTL inserted_at + INTERVAL 7 DAY DELETE matches the retention policy
  # documented in `server/data-export.md`. CH drops expired parts during
  # merges so we don't pay for a separate sweeper job.
  def up do
    create table(:webhook_delivery_attempts,
             primary_key: false,
             engine: "MergeTree",
             options: """
             PARTITION BY toYYYYMM(inserted_at)
             ORDER BY (webhook_endpoint_id, inserted_at)
             TTL inserted_at + INTERVAL 7 DAY DELETE
             """
           ) do
      # Stable row identifier; the per-event detail page navigates by it.
      add :id, :uuid, null: false

      # FK back to the PG `webhook_endpoints.id` (not enforced cross-DB,
      # but it's the partition key for all reads).
      add :webhook_endpoint_id, :uuid, null: false

      # Event id minted by `Tuist.Webhooks.Dispatcher` (UUIDv4, stored as
      # `String` so the dashboard's substring search stays trivial).
      add :event_id, :string, null: false

      # `LowCardinality(String)` — small fixed catalog (`test_case.created`,
      # `test_case.updated`, `preview.uploaded`, `preview.deleted`). Cheap
      # to introduce a new event type without a schema migration.
      add :event_type, :"LowCardinality(String)", null: false

      # 1..7 per the `DeliveryWorker` backoff schedule.
      add :attempt, :UInt8, null: false

      # `delivered` (2xx) or `failed` (non-2xx, transport error, SSRF
      # block). Higher-level lifecycle states live on the Oban job.
      add :status, :"LowCardinality(String)", null: false

      # Request payload Tuist sent — the signed JSON envelope.
      add :request_body, :string, null: false, default: ""

      # HTTP request headers as a JSON-encoded `String`. We don't need
      # CH's `Map` type — headers are rendered as-is on the event detail
      # page after a single JSON decode.
      add :request_headers, :string, null: false, default: ""

      # `0` is the sentinel for "no HTTP response received" (network
      # error, SSRF reject, timeout). Saves a `Nullable(...)` wrapper —
      # consumers branch on `> 0` to decide whether to render the code.
      add :response_status, :UInt16, null: false, default: 0

      # JSON-encoded response headers; empty string when no response
      # came back.
      add :response_headers, :string, null: false, default: ""

      # Truncated upstream at 64KiB by the worker.
      add :response_body, :string, null: false, default: ""

      # Empty string when the attempt succeeded.
      add :error, :string, null: false, default: ""

      add :duration_ms, :UInt32, null: false, default: 0

      add :inserted_at, :"DateTime64(6, 'UTC')",
        null: false,
        default: fragment("now64(6)")
    end

    # Skip index on event_type so the "filter by event type" path on the
    # dashboard avoids reading parts that don't contain the type.
    execute(
      "ALTER TABLE webhook_delivery_attempts ADD INDEX idx_event_type (event_type) TYPE set(8) GRANULARITY 4"
    )

    # Same idea for status — only two values, but the index lets the
    # "failed only" chart query skip parts with no failures.
    execute(
      "ALTER TABLE webhook_delivery_attempts ADD INDEX idx_status (status) TYPE set(2) GRANULARITY 4"
    )
  end

  def down do
    drop table(:webhook_delivery_attempts)
  end
end
