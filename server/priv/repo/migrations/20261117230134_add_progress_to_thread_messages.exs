defmodule Tuist.Repo.Migrations.AddProgressToThreadMessages do
  use Ecto.Migration

  # A `progress` message's plan (`Tuist.Threads.update_progress/2`): its
  # steps with their states; its body is the plan as a Markdown checklist.
  def change do
    alter table(:thread_messages) do
      add :progress, :map
    end
  end
end
