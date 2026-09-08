defmodule Tuist.Runners.Workers.UnstartedExecutionsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Workers.UnstartedExecutionsWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  @linux_resources %{platform: :linux, vcpus: 1, memory_gb: 1}

  defp lifecycle_attrs(account, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-a",
      platform: "linux",
      vcpus: 1,
      memory_gb: 1,
      repository: "acme/cli"
    }
  end

  # The strand this sweep exists for, built the way the webhook path left
  # it before it started the executed job: the claim records the
  # execution and the executed job's row learned the runner, but nothing
  # moved that row out of `queued`, so it reads Queued while the build
  # runs.
  defp strand_executing!(account, claimed_job_id, executed_job_id, pod_name, runner_name) do
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, claimed_job_id))
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, executed_job_id))
    {:ok, claim} = Claims.attempt(claimed_job_id, account.id, "fleet-a", pod_name, @linux_resources)
    :ok = Claims.mark_running(claimed_job_id, runner_name, claim.claimed_at)
    :ok = WorkflowJobs.record_execution(runner_name, executed_job_id, account.id)

    Repo.update_all(from(c in Claim, where: c.pod_name == ^pod_name),
      set: [executed_workflow_job_id: executed_job_id]
    )

    :ok
  end

  describe "perform/1" do
    test "starts a queued row a live claim proves is executing" do
      account = account_fixture()
      strand_executing!(account, 8001, 8002, "pod-1", "runner-stuck")

      assert :ok = perform_job(UnstartedExecutionsWorker, %{})

      row = Repo.get!(WorkflowJob, 8002)
      assert row.status == "running"
      assert row.runner_name == "runner-stuck"
      assert row.pod_name == "pod-1"
      assert %DateTime{} = row.started_at
    end

    test "leaves the claim and the displaced job alone" do
      account = account_fixture()
      strand_executing!(account, 8011, 8012, "pod-1", "runner-keep")

      assert :ok = perform_job(UnstartedExecutionsWorker, %{})

      assert Claims.counts_per_account() == %{account.id => 1}
      assert Repo.get!(WorkflowJob, 8011).status == "running"
    end

    test "does nothing when every row already agrees with its claim" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 8021))
      {:ok, claim} = Claims.attempt(8021, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(8021, "runner-matched", claim.claimed_at)
      :ok = WorkflowJobs.record_execution("runner-matched", 8021, account.id)

      assert :ok = perform_job(UnstartedExecutionsWorker, %{})

      assert Repo.get!(WorkflowJob, 8021).status == "running"
    end

    test "cannot resurrect a row a completion already settled" do
      account = account_fixture()
      strand_executing!(account, 8031, 8032, "pod-1", "runner-late")
      :ok = WorkflowJobs.record_completed(lifecycle_attrs(account, 8032), "success", DateTime.utc_now())

      assert :ok = perform_job(UnstartedExecutionsWorker, %{})

      assert Repo.get!(WorkflowJob, 8032).status == "completed"
    end
  end
end
