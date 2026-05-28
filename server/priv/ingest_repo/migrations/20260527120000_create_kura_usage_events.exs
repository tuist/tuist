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

    create table(:kura_usage_daily_stats,
             primary_key: false,
             engine: "AggregatingMergeTree",
             options:
               "ORDER BY (account_id, project_id, date, region, traffic_plane, direction, operation, protocol, artifact_kind)"
           ) do
      add :account_id, :Int64
      add :project_id, :Int64
      add :date, :date
      add :region, :string
      add :traffic_plane, :string
      add :direction, :string
      add :operation, :string
      add :protocol, :string
      add :artifact_kind, :string
      add :total_bytes, :"SimpleAggregateFunction(sum, UInt64)"
      add :request_count, :"SimpleAggregateFunction(sum, UInt64)"
    end

    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS kura_usage_daily_stats_mv
    TO kura_usage_daily_stats
    AS SELECT
      account_id,
      project_id,
      toDate(window_start) AS date,
      region,
      traffic_plane,
      direction,
      operation,
      protocol,
      artifact_kind,
      sum(bytes) AS total_bytes,
      sum(request_count) AS request_count
    FROM kura_usage_events
    GROUP BY account_id, project_id, date, region, traffic_plane, direction, operation, protocol, artifact_kind
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS kura_usage_daily_stats_mv"
    drop table(:kura_usage_daily_stats)
    drop table(:kura_usage_events)
  end
end
