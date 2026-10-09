defmodule Tuist.Repo.Migrations.IndexClosedRunnerSessionsByPod do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Interrupted concurrent builds can leave an INVALID index. After confirming
  # no build is active, remove only that invalid index concurrently and retry.
  # Recovery steps live in server/priv/AGENTS.md; do not use create_if_not_exists.
  def change do
    create index(:runner_sessions, [:pod_name, :started_at],
             name: :runner_sessions_closed_pod_name_started_at_index,
             where: "ended_at IS NOT NULL",
             concurrently: true
           )
  end
end
