defmodule Tuist.IngestRepo.Migrations.ChangeGradleTasksStartedAtToDatetime646 do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE gradle_tasks MODIFY COLUMN started_at Nullable(DateTime64(6))",
      "ALTER TABLE gradle_tasks MODIFY COLUMN started_at Nullable(DateTime64(3))"
    )
  end
end
