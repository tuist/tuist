defmodule Tuist.IngestRepo.Migrations.CreateCasEntriesTable do
  use Ecto.Migration

  def change do
    create table(:cas_entries,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (cas_id, project_id, inserted_at) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :id, :uuid, null: false
      add :cas_id, :string, null: false
      add :value, :string, null: false
      add :project_id, :Int64, null: false

      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
