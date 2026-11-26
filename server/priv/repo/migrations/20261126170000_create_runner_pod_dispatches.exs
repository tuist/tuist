defmodule Tuist.Repo.Migrations.CreateRunnerPodDispatches do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # One row per runner Pod that was handed a runner credential. A Pod
  # runs at most one job, and its dispatch token lives in the same guest
  # as the tenant's code, so `Tuist.Runners.Claims.attempt/6` refuses any
  # further claim from a Pod named here. Unlike `runner_claims`, the row
  # outlives the job: the claim is deleted on completion while the Pod's
  # ServiceAccount, and so its token, still exists. The row is deleted
  # only once the Pod is gone (`PodReconciliationWorker`), which is when
  # its bound token stops authenticating.
  #
  # No foreign key on `account_id`: deleting the account mid-job must not
  # delete the record that refuses the Pod's token.
  def change do
    create table(:runner_pod_dispatches, primary_key: false) do
      add :pod_name, :string, primary_key: true
      add :account_id, :bigint, null: false
      add :workflow_job_id, :bigint, null: false
      add :dispatched_at, :timestamptz, null: false
    end

    create index(:runner_pod_dispatches, [:dispatched_at], concurrently: true)
  end
end
