defmodule Tuist.Repo.Migrations.AddLifecycleStateToRunnerClaims do
  use Ecto.Migration

  # Distinguish a freshly-claimed row (still in the mint window)
  # from one that already transitioned to `running`. The
  # stale-claims worker only ever reaps the former — a job that's
  # been running for an hour is healthy, not stuck mid-mint, and
  # reaping it would free its cap slot and over-schedule the
  # account.
  #
  # Lifecycle transitions (Postgres):
  #
  #   claim attempt    → INSERT (default 'claimed')
  #   JIT mint OK      → UPDATE lifecycle_state='running', runner_name=...
  #   webhook complete → DELETE
  #   stale reaper     → DELETE WHERE lifecycle_state='claimed' AND old
  #
  # `lifecycle_state` is `LowCardinality`-ish (two values today,
  # maybe a third later); plain :string with the partial index
  # below keeps the cap-counting query fast and the schema easy
  # to evolve.
  def change do
    alter table(:runner_claims) do
      add :lifecycle_state, :string, null: false, default: "claimed"
      # The GH runner name we registered for this claim. Set when
      # `lifecycle_state` flips to `running`; lets ops correlate
      # a stuck PG row to the runner in the GitHub Actions UI.
      add :runner_name, :string, null: false, default: ""
    end

    # Partial index — the stale-claim reaper scans only rows in
    # `claimed` state. A full `(claimed_at)` index would also
    # match `running` rows, which the reaper now skips; partialing
    # on the lifecycle bit keeps the scan tight.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:claimed_at],
             where: "lifecycle_state = 'claimed'",
             name: :runner_claims_claimed_lifecycle_idx
           )

    # Pod-in-use lookup: the claim transaction rejects a second
    # attempt from the same pod while one is live. Partial-uniqueness
    # on (pod_name) for claims that have actually been registered
    # with GitHub (lifecycle_state='running') would be ideal but
    # we also want to block double-claims during the brief
    # `claimed` window. A non-unique index covers the SELECT path
    # without preventing the legitimate case of a pod's claim
    # being re-issued after a release / complete cycle.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:pod_name])
  end
end
