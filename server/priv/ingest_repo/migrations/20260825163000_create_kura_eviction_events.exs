defmodule Tuist.IngestRepo.Migrations.CreateKuraEvictionEvents do
  use Ecto.Migration

  # One row per segment a Kura node evicted under ring size pressure. The
  # column pair (evicted_at, newest_content_at) is the claim sizing signal:
  # their difference is how soon after being written an artifact was shed,
  # which per-plan retention floors are enforced against.
  #
  # Nodes deliver at-least-once with a deterministic event_id per evicted
  # segment, so the ReplacingMergeTree collapses redeliveries the same way
  # kura_usage_events does. The 180-day TTL comfortably covers the longest
  # policy window (90 days) plus calibration headroom.
  def up do
    create table(:kura_eviction_events,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options:
               "PARTITION BY toYYYYMM(evicted_at) ORDER BY (event_id) TTL toDateTime(inserted_at) + INTERVAL 180 DAY"
           ) do
      add :event_id, :string
      add :account_id, :Int64
      add :node_id, :string
      add :region, :string
      add :segment_id, :string
      add :reason, :string
      add :evicted_at, :naive_datetime
      add :segment_created_at, :naive_datetime
      add :newest_content_at, :naive_datetime
      add :artifact_count, :UInt64
      add :bytes, :UInt64
      add :inserted_at, :naive_datetime
    end
  end

  def down do
    drop table(:kura_eviction_events)
  end
end
