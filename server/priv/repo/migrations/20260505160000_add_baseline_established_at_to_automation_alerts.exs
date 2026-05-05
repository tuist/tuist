defmodule Tuist.Repo.Migrations.AddBaselineEstablishedAtToAutomationAlerts do
  use Ecto.Migration

  def up do
    alter table(:automation_alerts) do
      add :baseline_established_at, :timestamptz
    end

    # Existing alerts have already been firing on the "current state matches"
    # rule — backfill with NOW() so they don't re-baseline on first eval after
    # this migration deploys (which would silently swallow whatever they're
    # currently tracking).
    execute("UPDATE automation_alerts SET baseline_established_at = NOW()")
  end

  def down do
    alter table(:automation_alerts) do
      remove :baseline_established_at
    end
  end
end
