defmodule Tuist.IngestRepo.Migrations.CreateAutomationStates do
  use Ecto.Migration

  def up do
    create table(:automation_states,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "ORDER BY (automation_id, test_case_id, id)"
           ) do
      add :id, :uuid, null: false
      add :automation_id, :uuid, null: false
      add :test_case_id, :uuid, null: false
      add :status, :"LowCardinality(String)", null: false, default: "triggered"
      add :triggered_at, :"DateTime64(6)", null: false
      add :recovered_at, :"Nullable(DateTime64(6))"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    execute(
      "ALTER TABLE automation_states ADD INDEX idx_automation_id (automation_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE automation_states ADD INDEX idx_test_case_id (test_case_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:automation_states)
  end
end
