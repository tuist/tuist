defmodule Tuist.Repo.Migrations.AddRunnerToThreads do
  use Ecto.Migration

  # excellent_migrations:safety-assured-for-this-file index_not_concurrently
  # Threads is young and small; the index builds in moments.
  def change do
    alter table(:threads) do
      # The person's machine the thread runs on, when they chose one.
      add :runner_id, references(:thread_runners, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:threads, [:runner_id])
  end
end
