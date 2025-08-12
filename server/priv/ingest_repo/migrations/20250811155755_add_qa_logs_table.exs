defmodule Tuist.IngestRepo.Migrations.AddQaLogsTable do
  use Ecto.Migration

  def change do
    create table(:qa_logs,
             primary_key: false,
             engine: "MergeTree",
             options:
               "ORDER BY (project_id, qa_run_id, timestamp) TTL inserted_at + INTERVAL 14 DAY"
           ) do
      add :project_id, :Int64, null: false
      add :qa_run_id, :uuid, null: false
      add :message, :string, null: false
      add :level, :"Enum8('debug' = 0, 'info' = 1, 'warning' = 2, 'error' = 3)", null: false
      add :timestamp, :naive_datetime, null: false
      add :inserted_at, :naive_datetime, default: fragment("now()")
    end
  end
end
