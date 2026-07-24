defmodule Tuist.Repo.Migrations.AssertRollingAutomationWindowsFitActiveAggregate do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      repo().query!("""
      SELECT id::text
      FROM automation_alerts
      WHERE trigger_config->>'window_type' = 'rolling'
        AND CASE
          WHEN jsonb_typeof(trigger_config->'rolling_window_size') = 'number' THEN
            (trigger_config->>'rolling_window_size')::numeric < 1
            OR (trigger_config->>'rolling_window_size')::numeric > 99
            OR (trigger_config->>'rolling_window_size')::numeric
              <> trunc((trigger_config->>'rolling_window_size')::numeric)
          ELSE TRUE
        END
      ORDER BY id
      """)

    if rows != [] do
      alert_ids = Enum.map_join(rows, ", ", fn [alert_id] -> alert_id end)

      raise Ecto.MigrationError,
            "rolling automation alerts fall outside the active 1 to 99-run range: #{alert_ids}"
    end
  end

  def down, do: :ok
end
