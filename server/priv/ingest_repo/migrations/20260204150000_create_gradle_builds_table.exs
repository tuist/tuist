defmodule Tuist.IngestRepo.Migrations.CreateGradleBuildsTable do
  use Ecto.Migration

  def change do
    create table(:gradle_builds,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :account_id, :Int64, null: false
      add :duration_ms, :UInt64, null: false
      add :gradle_version, :"Nullable(String)"
      add :java_version, :"Nullable(String)"
      add :is_ci, :Bool, null: false, default: false
      add :status, :"Enum8('success' = 0, 'failure' = 1, 'cancelled' = 2)", null: false
      add :git_branch, :"Nullable(String)"
      add :git_commit_sha, :"Nullable(String)"
      add :git_ref, :"Nullable(String)"
      add :tasks_local_hit_count, :UInt32, null: false, default: 0
      add :tasks_remote_hit_count, :UInt32, null: false, default: 0
      add :tasks_up_to_date_count, :UInt32, null: false, default: 0
      add :tasks_executed_count, :UInt32, null: false, default: 0
      add :tasks_failed_count, :UInt32, null: false, default: 0
      add :tasks_skipped_count, :UInt32, null: false, default: 0
      add :tasks_no_source_count, :UInt32, null: false, default: 0
      add :cacheable_tasks_count, :UInt32, null: false, default: 0
      add :avoidance_savings_ms, :UInt64, null: false, default: 0
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
