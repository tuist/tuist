defmodule Tuist.Repo.Migrations.AddCacheableTasksCountsToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :cacheable_task_remote_hits_count, :integer, default: 0, null: false
      add :cacheable_task_local_hits_count, :integer, default: 0, null: false
      add :cacheable_tasks_count, :integer, default: 0, null: false
    end
  end
end
