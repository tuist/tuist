defmodule Tuist.IngestRepo.Migrations.CreateAutomationAlertEvents do
  use Ecto.Migration

  def up do
    create table(:automation_alert_events,
             primary_key: false,
             engine: "MergeTree()",
             options: "ORDER BY (alert_id, test_case_id, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :alert_id, :uuid, null: false
      add :test_case_id, :uuid, null: false
      add :status, :"LowCardinality(String)", null: false, default: "triggered"
      add :triggered_at, :"DateTime64(6)", null: false
      add :recovered_at, :"Nullable(DateTime64(6))"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    execute(
      "ALTER TABLE automation_alert_events ADD INDEX idx_alert_id (alert_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE automation_alert_events ADD INDEX idx_test_case_id (test_case_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    drop table(:automation_alert_events)
  end
end
