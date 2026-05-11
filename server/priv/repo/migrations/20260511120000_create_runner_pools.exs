defmodule Tuist.Repo.Migrations.CreateRunnerPools do
  use Ecto.Migration

  # Per-customer runner-pool config. The Tuist server is the system of
  # record; `Tuist.Runners.PoolReconciler` syncs each row into a
  # matching `RunnerPool` CR in the cluster's runners namespace, which
  # the runners-controller picks up to maintain `min_warm` pre-bound
  # Pods. Onboarding a new customer becomes an INSERT here.
  #
  # `role = 'customer'` rows are per-org reservations; `role =
  # 'shared_warm'` rows hold the cluster-wide standby pool that the
  # dispatch endpoint claims Bursts against. `account_id` is NULL for
  # SharedWarm (it isn't owned by any one customer).
  def change do
    create table(:runner_pools) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: true
      add :name, :string, null: false
      add :role, :string, null: false, default: "customer"
      add :owner, :string, null: false, default: ""
      add :labels, {:array, :string}, null: false, default: []
      add :min_warm, :integer, null: false, default: 0
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
