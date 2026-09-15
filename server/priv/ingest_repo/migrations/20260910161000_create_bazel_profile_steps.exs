defmodule Tuist.IngestRepo.Migrations.CreateBazelProfileSteps do
  use Ecto.Migration

  def change do
    create table(:bazel_profile_steps,
             primary_key: false,
             engine: "ReplacingMergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, invocation_id, version, event_id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :project_id, :Int64, null: false
      add :invocation_id, :String, null: false
      add :version, :String, null: false
      add :event_id, :String, null: false
      add :title, :String, null: false
      add :project, :String, null: false
      add :target, :String, null: false
      add :category, :String, null: false
      add :primary_output, :String, null: false
      add :start_ms, :Float64, null: false
      add :duration_ms, :Float64, null: false
      add :profile_started_at_ms, :UInt64, null: false
      add :inserted_at, :DateTime, null: false
    end
  end
end
