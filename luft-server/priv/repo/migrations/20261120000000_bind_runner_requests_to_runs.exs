defmodule LuftServer.Repo.Migrations.BindRunnerRequestsToRuns do
  use Ecto.Migration

  def change do
    alter table(:thread_runner_requests) do
      add :run_id, references(:thread_runs, type: :binary_id, on_delete: :delete_all)
      add :run_attempt, :integer
    end

    create index(:thread_runner_requests, [:run_id])

    # Old queued operations have no execution authority and must never replay.
    execute(
      "UPDATE thread_runner_requests SET status = 'cancelled' WHERE status IN ('pending', 'claimed')",
      "SELECT 1"
    )
  end
end
