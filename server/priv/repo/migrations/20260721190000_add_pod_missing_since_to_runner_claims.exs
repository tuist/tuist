defmodule Tuist.Repo.Migrations.AddPodMissingSinceToRunnerClaims do
  use Ecto.Migration

  def change do
    alter table(:runner_claims) do
      # First tick on which the claim's Pod was absent from a complete,
      # successful cluster read. NULL means "Pod observed present", which
      # is also the safe default for every existing row: the reconciler
      # has to observe an absence itself before it will act on one.
      #
      # This is durable rather than in-memory on purpose. The confirmation
      # rule is "absent across consecutive observations", and the server
      # runs multiple replicas, so the previous observation cannot live in
      # a process that may not handle the next tick.
      add :pod_missing_since, :timestamptz
    end

    # The reconciler's release pass filters on this column and it is NULL
    # for every healthy claim, so a partial index stays tiny.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:pod_missing_since], where: "pod_missing_since IS NOT NULL")
  end
end
