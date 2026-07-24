defmodule Tuist.Repo.Migrations.AssertRollingAutomationWindowsFitActiveAggregate do
  use Ecto.Migration

  @max_rolling_window_size 75

  def up do
    # This is repeated by the aggregate-retirement deployment. The first check
    # catches existing incompatible alerts before this application version
    # rolls out; the second closes the window in which an old pod could still
    # have written one during the rollout.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    execute("""
    DO $$
    DECLARE
      incompatible_alert_ids text;
    BEGIN
      SELECT string_agg(id::text, ', ' ORDER BY id::text)
      INTO incompatible_alert_ids
      FROM automation_alerts
      WHERE enabled
        AND trigger_config->>'window_type' = 'rolling'
        AND NOT CASE
          WHEN trigger_config->>'rolling_window_size' ~ '^[1-9][0-9]*$'
          THEN (trigger_config->>'rolling_window_size')::numeric BETWEEN 1 AND #{@max_rolling_window_size}
          ELSE false
        END;

      IF incompatible_alert_ids IS NOT NULL THEN
        RAISE EXCEPTION
          'Enabled rolling automation alerts must use windows between 1 and #{@max_rolling_window_size} before deployment. Incompatible alert IDs: %',
          incompatible_alert_ids;
      END IF;
    END
    $$;
    """)
  end

  def down do
    :ok
  end
end
