defmodule Tuist.Repo.Migrations.DropPgWebhookDeliveryAttemptsTable do
  use Ecto.Migration

  # `webhook_delivery_attempts` was originally created in Postgres by
  # `20260513150000_add_webhook_delivery_attempts_table.exs`. It was
  # moved to ClickHouse in the same release so the time-series reads on
  # the per-endpoint chart and the 7-day retention TTL can use the
  # column-store / merge engine instead of vacuuming PG bloat.
  #
  # `IF EXISTS` keeps this a no-op on fresh databases that never ran the
  # original create migration.
  def up do
    execute("DROP TABLE IF EXISTS webhook_delivery_attempts")
  end

  def down do
    # Intentionally no-op — recreating the empty PG shell on rollback
    # would just shadow the live ClickHouse table.
    :ok
  end
end
