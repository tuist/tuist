defmodule Tuist.IngestRepo.Migrations.CreateAutomationAlertEvents do
  use Ecto.Migration

  # Raw SQL with IF NOT EXISTS so the migration is idempotent — see
  # 20260410120000_add_state_to_test_cases.exs for the rationale (ClickHouse
  # DDL is non-transactional, so partial runs must be recoverable).
  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS automation_alert_events (
      id UUID,
      alert_id UUID,
      test_case_id UUID,
      status LowCardinality(String) DEFAULT 'triggered',
      triggered_at DateTime64(6),
      recovered_at Nullable(DateTime64(6)),
      inserted_at DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    ORDER BY (alert_id, test_case_id, inserted_at)
    """)

    execute(
      "ALTER TABLE automation_alert_events ADD INDEX IF NOT EXISTS idx_alert_id (alert_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE automation_alert_events ADD INDEX IF NOT EXISTS idx_test_case_id (test_case_id) TYPE bloom_filter GRANULARITY 4"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS automation_alert_events")
  end
end
