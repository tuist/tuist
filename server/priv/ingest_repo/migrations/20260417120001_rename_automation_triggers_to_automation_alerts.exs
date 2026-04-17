defmodule Tuist.IngestRepo.Migrations.RenameAutomationTriggersToAutomationAlerts do
  use Ecto.Migration

  def up do
    execute("RENAME TABLE automation_triggers TO automation_alerts")
  end

  def down do
    execute("RENAME TABLE automation_alerts TO automation_triggers")
  end
end
