defmodule Tuist.Repo.Migrations.CreateRunnerPools do
  use Ecto.Migration

  # Per-customer runner-pool config. The Tuist server is the system of
  # record; `Tuist.Runners.PoolReconciler` syncs each row into a
  # matching `RunnerPool` CR in the cluster's runners namespace, which
  # the runners-controller picks up. Onboarding a new customer becomes
  # an INSERT here.
  #
  # `role = 'customer'` rows are per-org capacity grants;
  # `role = 'shared_warm'` rows mark the cluster-wide standby pool the
  # dispatch endpoint claims Bursts against. `account_id` is NULL for
  # SharedWarm (it isn't owned by any one customer).
  #
  # No `min_warm` column: customer pools rely on the cluster's
  # SharedWarm standby for sub-10s cold-start, and the SharedWarm
  # pool's own standby size is an operator-visible chart value
  # (TUIST_RUNNERS_SHARED_WARM_SIZE), not a per-row knob.
  #
  # `max_concurrent` is the customer's hard ceiling on concurrent
  # runners across ALL their pools (a customer with multiple pools
  # for different macOS versions has one cap covering them all). The
  # dispatch handler counts non-terminal RunnerAssignment CRs by the
  # `tuist.dev/runner-pool-owner` label before creating a Burst.
  # nil = no cap.
  def change do
    create table(:runner_pools) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: true
      add :name, :string, null: false
      add :role, :string, null: false, default: "customer"
      add :owner, :string, null: false, default: ""
      add :labels, {:array, :string}, null: false, default: []
      add :max_concurrent, :integer
      add :runner_group_id, :bigint
      add :allowed_repos, {:array, :string}
      add :image, :string
      add :fleet_selector, :string
      add :pod_cpu_milli, :integer
      add :pod_memory_mb, :integer

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_pools, [:name])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_pools, [:account_id])

    # Belt-and-suspenders: at most one SharedWarm pool per cluster
    # today (it's a single global standby pool, sized by aggregate
    # burst rate). Postgres partial unique index enforces it.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_pools, [:role],
             where: "role = 'shared_warm'",
             name: :runner_pools_single_shared_warm
           )
  end
end
