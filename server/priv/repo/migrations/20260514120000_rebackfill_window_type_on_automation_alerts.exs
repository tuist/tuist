defmodule Tuist.Repo.Migrations.RebackfillWindowTypeOnAutomationAlerts do
  use Ecto.Migration

  @moduledoc """
  Re-runs the `window_type` backfill from `20260508120000` to catch rows
  that slipped past the original pass. Production observed a flakiness
  alert whose `trigger_config` and `recovery_config` still lacked
  `window_type`, crashing `AlertEvaluationWorker.establish_baseline/2`
  on every cadence. The statements are idempotent, so re-running is safe
  for already-backfilled rows.
  """

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET trigger_config = trigger_config || jsonb_build_object('window_type', 'last_days')
    WHERE NOT (trigger_config ? 'window_type')
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET recovery_config =
      (recovery_config - 'days_without_trigger')
      || jsonb_build_object(
        'window',
        (recovery_config->>'days_without_trigger') || 'd'
      )
    WHERE recovery_enabled = true
      AND NOT (recovery_config ? 'window')
      AND recovery_config ? 'days_without_trigger'
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET recovery_config = recovery_config || jsonb_build_object('window_type', 'last_days')
    WHERE recovery_enabled = true
      AND NOT (recovery_config ? 'window_type')
    """)
  end

  def down do
    :ok
  end
end
