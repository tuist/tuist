defmodule Tuist.IngestRepo.Migrations.AddGradleFailureMessages do
  use Ecto.Migration

  # Bounded, sanitized failure messages (the exception message and cause chain) of failed
  # Gradle tasks and configuration operations. Existing rows keep empty defaults.
  def up do
    for table <- ["gradle_tasks", "gradle_configuration_operations"] do
      execute """
      ALTER TABLE #{table}
        ADD COLUMN IF NOT EXISTS failure_message String DEFAULT '',
        ADD COLUMN IF NOT EXISTS failure_message_truncated Bool DEFAULT false
      """
    end
  end

  def down do
    for table <- ["gradle_tasks", "gradle_configuration_operations"] do
      execute "ALTER TABLE #{table} DROP COLUMN IF EXISTS failure_message, DROP COLUMN IF EXISTS failure_message_truncated"
    end
  end
end
