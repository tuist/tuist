defmodule Tuist.Repo.Migrations.AddPodNameIndexToRunnerSessions do
  use Ecto.Migration

  # `RunnerSessions.close_by_pod_name/2` lands on the
  # `/api/internal/runners/pods/stopped` hot path — the
  # runners-controller calls it on every Pod terminal-phase
  # transition. The lookup is `WHERE pod_name = $1 AND ended_at IS
  # NULL ORDER BY started_at DESC LIMIT 1`; index it on `pod_name`
  # so the close cost stays O(log n) regardless of how much history
  # the table has accumulated. Partial-on-open keeps the index
  # small — closed sessions are 99% of the table over time and we
  # never look them up by pod_name.
  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:pod_name], where: "ended_at IS NULL")
  end
end
