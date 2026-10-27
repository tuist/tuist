defmodule Tuist.IngestRepo.Migrations.CreateKuraUsageEvents do
  use Ecto.Migration

  def up do
    create table(:kura_usage_events,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "PARTITION BY toYYYYMM(window_start) ORDER BY (event_id)"
           ) do
      add :event_id, :string
      add :account_id, :Int64
      add :project_id, :Int64
      add :node_id, :string
      add :region, :string
      add :traffic_plane, :string
      add :direction, :string
      add :operation, :string
      add :protocol, :string
      add :artifact_kind, :string
      add :bytes, :UInt64
      add :request_count, :UInt64
      add :window_start, :naive_datetime
      add :window_seconds, :UInt32
      add :inserted_at, :naive_datetime
    end
  end

  def down do
    drop table(:kura_usage_events)
  end
end
