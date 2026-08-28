defmodule Tuist.IngestRepo.Migrations.CreateBazelInvocationLogsTable do
  use Ecto.Migration

  def change do
    create table(:bazel_invocation_logs,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(observed_at) ORDER BY (project_id, invocation_id, sequence_number) TTL observed_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :invocation_id, :string, null: false
      add :sequence_number, :UInt64, null: false
      add :stream, :"LowCardinality(String)", null: false
      add :message, :string, null: false
      add :project_id, :Int64, null: false
      add :observed_at, :naive_datetime, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
