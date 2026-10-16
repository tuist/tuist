Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261014160000_enqueue_runner_job_replica_repair.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.EnqueueRunnerJobReplicaRepairTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo.Migrations.EnqueueRunnerJobReplicaRepair
  alias Tuist.Runners.Workers.RepairReplicaDivergenceWorker
  alias Tuist.Runners.WorkflowJobs

  test "queues one full-history repair when runner jobs exist" do
    account = account_fixture()

    :ok =
      WorkflowJobs.upsert_queued(%{workflow_job_id: 9_140_101, account_id: account.id, fleet_name: "fleet-repair"})

    EnqueueRunnerJobReplicaRepair.enqueue_repair!(Repo)

    assert [%{args: %{"enqueued_after" => "2026-01-01T00:00:00Z"}, queue: "default", max_attempts: 20}] =
             all_enqueued(worker: RepairReplicaDivergenceWorker)
  end

  test "queues nothing when there are no runner jobs" do
    EnqueueRunnerJobReplicaRepair.enqueue_repair!(Repo)

    assert [] = all_enqueued(worker: RepairReplicaDivergenceWorker)
  end
end
