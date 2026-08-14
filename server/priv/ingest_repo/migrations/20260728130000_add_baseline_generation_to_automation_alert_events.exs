defmodule Tuist.IngestRepo.Migrations.AddBaselineGenerationToAutomationAlertEvents do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE automation_alert_events
    ADD COLUMN IF NOT EXISTS baseline_generation UInt32 DEFAULT 0 AFTER alert_id
    """)

    execute("""
    ALTER TABLE automation_alert_events
    MODIFY SETTING
      non_replicated_deduplication_window = 1000,
      replicated_deduplication_window = 1000
    """)
  end

  def down do
    execute("""
    ALTER TABLE automation_alert_events
    DROP COLUMN IF EXISTS baseline_generation
    """)
  end
end
