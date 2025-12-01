defmodule Tuist.IngestRepo.Migrations.CreateCasAnalyticsTable do
  use Ecto.Migration

  def change do
    create table(:cas_events,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, action, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :action, :"Enum8('upload' = 0, 'download' = 1)", null: false
      add :size, :Int64, null: false
      add :cas_id, :string, null: false
      add :project_id, :Int64, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
