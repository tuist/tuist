defmodule Tuist.IngestRepo.Migrations.CreateBazelActions do
  use Ecto.Migration

  def change do
    create table(:bazel_actions,
             primary_key: false,
             engine: "ReplacingMergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, invocation_id, primary_output, started_at_ms) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :project_id, :Int64, null: false
      add :invocation_id, :String, null: false
      add :primary_output, :String, null: false
      add :started_at_ms, :UInt64, null: false
      add :status, :String, null: false
      add :log, :String, null: false
      add :log_truncated, :Bool, default: false
      add :inserted_at, :DateTime, null: false
    end
  end
end
