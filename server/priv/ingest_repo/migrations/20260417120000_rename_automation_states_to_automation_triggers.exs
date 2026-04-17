defmodule Tuist.IngestRepo.Migrations.RenameAutomationStatesToAutomationTriggers do
  use Ecto.Migration

  def up do
    execute("RENAME TABLE automation_states TO automation_triggers")
  end

  def down do
    execute("RENAME TABLE automation_triggers TO automation_states")
  end
end
