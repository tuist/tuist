defmodule Tuist.IngestRepo.Migrations.CreateBazelTestResultsTable do
  use Ecto.Migration

  def change do
    create table(:bazel_test_results,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(finished_at) ORDER BY (project_id, finished_at, invocation_id, target_label) TTL finished_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :invocation_id, :string, null: false
      add :target_label, :string, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1, 'flaky' = 2, 'skipped' = 3)", null: false
      add :duration_ms, :UInt64, null: false
      add :attempt_count, :UInt32, null: false
      add :finished_at, :naive_datetime, null: false
      add :project_id, :Int64, null: false
      add :account_handle, :string, null: false
      add :project_handle, :string, null: false
      add :cache_endpoint, :"LowCardinality(String)", null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
