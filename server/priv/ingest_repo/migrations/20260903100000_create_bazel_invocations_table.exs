defmodule Tuist.IngestRepo.Migrations.CreateBazelInvocationsTable do
  use Ecto.Migration

  def change do
    create table(:bazel_invocations,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, finished_at, invocation_id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :invocation_id, :string, null: false
      add :command, :"LowCardinality(String)", null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :exit_code, :Int32, null: false
      add :started_at, :naive_datetime, null: false
      add :finished_at, :naive_datetime, null: false
      add :duration_ms, :UInt64, null: false
      add :project_id, :Int64, null: false
      add :account_handle, :string, null: false
      add :project_handle, :string, null: false
      add :cache_endpoint, :"LowCardinality(String)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
