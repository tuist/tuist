defmodule Tuist.IngestRepo.Migrations.CreateTestRunDestinationsTable do
  use Ecto.Migration

  def up do
    create table(:test_run_destinations,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (test_run_id, inserted_at, id)"
           ) do
      add :id, :uuid, null: false
      add :test_run_id, :uuid, null: false
      add :name, :string, null: false
      add :platform, :"LowCardinality(String)", null: false
      add :os_version, :string, null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:test_run_destinations)
  end
end
