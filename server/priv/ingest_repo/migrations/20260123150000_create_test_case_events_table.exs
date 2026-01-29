defmodule Tuist.IngestRepo.Migrations.CreateTestCaseEventsTable do
  use Ecto.Migration

  def up do
    create table(:test_case_events,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "ORDER BY (test_case_id, event_type, id)"
           ) do
      add :id, :uuid, null: false
      add :test_case_id, :uuid, null: false
      add :event_type, :"LowCardinality(String)", null: false
      add :actor_id, :"Nullable(Int64)"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    execute(
      "ALTER TABLE test_case_events ADD INDEX idx_test_case_id (test_case_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:test_case_events)
  end
end
