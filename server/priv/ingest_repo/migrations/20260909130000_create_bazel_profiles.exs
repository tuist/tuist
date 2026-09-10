defmodule Tuist.IngestRepo.Migrations.CreateBazelProfiles do
  use Ecto.Migration

  def change do
    create table(:bazel_profiles,
             primary_key: false,
             engine: "ReplacingMergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, invocation_id) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :project_id, :Int64, null: false
      add :invocation_id, :String, null: false
      add :payload, :String, null: false
      add :inserted_at, :DateTime, null: false
    end
  end
end
