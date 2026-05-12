defmodule Tuist.Repo.Migrations.BackfillWindowTypeOnAutomationAlerts do
  use Ecto.Migration

  @moduledoc """
  Backfills `window_type: "last_days"` on every automation_alert row whose
  `trigger_config` (or `recovery_config`, when recovery is enabled) was
  written before the rolling-window option existed. Also normalises the
  legacy `recovery_config.days_without_trigger` integer into the current
  `window: "Nd"` string so all rows share one shape.

  After this runs, every persisted row has an explicit `window_type` and the
  scattered "default to last_days" branches in the changeset / form / worker
  are only defensive — they're no longer load-bearing for production data.
  """

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET trigger_config = trigger_config || jsonb_build_object('window_type', 'last_days')
    WHERE NOT (trigger_config ? 'window_type')
    """)

    # Promote the legacy `days_without_trigger` integer to `window: "Nd"` so
    # the recovery_config shape matches what every code path now writes.
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
    # Stripping the backfilled keys puts rows back in the pre-migration shape.
    # `days_without_trigger` is not restored — the rename predates this column
    # by months and the application has long since stopped writing it.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET trigger_config = trigger_config - 'window_type'
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE automation_alerts
    SET recovery_config = recovery_config - 'window_type'
    """)
  end
end
