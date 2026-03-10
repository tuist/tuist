defmodule Tuist.IngestRepo.Migrations.AddRequestedTasksToGradleBuilds do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS requested_tasks Array(String) DEFAULT []"
    )
  end

  def down do
    execute("ALTER TABLE gradle_builds DROP COLUMN IF EXISTS requested_tasks")
  end
end
