defmodule Tuist.Repo.Migrations.ReassertRollingAutomationWindowsFitActiveAggregate do
  use Ecto.Migration

  @max_rolling_window_size 75

  def up, do: assert_compatible_alerts!(repo())

  def assert_compatible_alerts!(repo) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      repo.query!("""
      SELECT id::text
      FROM automation_alerts
      WHERE enabled
        AND trigger_config->>'window_type' = 'rolling'
        AND CASE
          WHEN jsonb_typeof(trigger_config->'rolling_window_size') = 'number' THEN
            (trigger_config->>'rolling_window_size')::numeric < 1
            OR (trigger_config->>'rolling_window_size')::numeric > #{@max_rolling_window_size}
            OR (trigger_config->>'rolling_window_size')::numeric
              <> trunc((trigger_config->>'rolling_window_size')::numeric)
          ELSE TRUE
        END
      ORDER BY id
      """)

    if rows != [] do
      alert_ids = Enum.map_join(rows, ", ", fn [alert_id] -> alert_id end)

      raise Ecto.MigrationError,
            "enabled rolling automation alerts fall outside the active 1 to #{@max_rolling_window_size}-run range; disable them or reduce their rolling trigger windows before retrying. Alert IDs: #{alert_ids}"
    end
  end

  def down, do: :ok
end
