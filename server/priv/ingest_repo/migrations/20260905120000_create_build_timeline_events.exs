defmodule Tuist.IngestRepo.Migrations.CreateBuildTimelineEvents do
  use Ecto.Migration

  def change do
    create table(:build_timeline_events,
             primary_key: false,
             engine: "ReplacingMergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (build_run_id, event_id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :build_run_id, :UUID, null: false
      add :event_id, :UInt64, null: false
      add :title, :String, null: false
      add :target, :String, null: false
      add :project, :String, null: false
      add :category, :String, null: false
      add :start_ms, :Float64, null: false
      add :duration_ms, :Float64, null: false
      add :status, :String, null: false
      add :inserted_at, :DateTime, null: false
    end
  end
end
