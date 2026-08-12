defmodule Tuist.Repo.Migrations.AddPodMissingSinceToRunnerSessions do
  use Ecto.Migration

  def change do
    alter table(:runner_sessions) do
      # First tick on which the session's Pod was absent from a
      # complete, successful cluster read. NULL means "Pod observed
      # present", which is also the safe default for every existing
      # row: the reaper has to observe an absence itself before it
      # closes anything.
      #
      # Durable rather than in-memory for the same reason as the
      # matching column on `runner_claims`: the rule is "absent across
      # consecutive observations", and the server runs multiple
      # replicas, so the previous observation cannot live in a process
      # that may not handle the next tick.
      add :pod_missing_since, :timestamptz
    end

    # The reaper's close pass filters on this column and it is NULL for
    # every healthy session, so a partial index stays tiny.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:pod_missing_since], where: "pod_missing_since IS NOT NULL")
  end
end
