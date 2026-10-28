defmodule Tuist.IngestRepo.Migrations.CreateKuraStorageSnapshots do
  use Ecto.Migration

  # Periodic ring-occupancy snapshots from Kura nodes. Occupancy is what tells
  # an oversized claim (stays low, nothing evicts) from an undersized one
  # (full and churning), so it is the shrink half of claim sizing where
  # kura_eviction_events is the grow half.
  #
  # Timestamps that can be absent on an empty ring (oldest_segment_created_at,
  # newest_content_at) are encoded as the epoch rather than Nullable, matching
  # the ClickHouse column style of the sibling tables; readers gate on
  # live_segment_count instead.
  def up do
    create table(:kura_storage_snapshots,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options:
               "PARTITION BY toYYYYMM(captured_at) ORDER BY (event_id) TTL toDateTime(inserted_at) + INTERVAL 180 DAY"
           ) do
      add :event_id, :string
      add :account_id, :Int64
      add :node_id, :string
      add :region, :string
      add :captured_at, :naive_datetime
      add :ring_budget_bytes, :UInt64
      add :desired_segment_count, :UInt64
      add :live_segment_count, :UInt64
      add :live_segment_bytes, :UInt64
      add :oldest_segment_created_at, :naive_datetime
      add :newest_content_at, :naive_datetime
      add :inserted_at, :naive_datetime
    end
  end

  def down do
    drop table(:kura_storage_snapshots)
  end
end
