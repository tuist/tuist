defmodule Tuist.Runners.Workers.UnstartedExecutionsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
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

  # The runner shuffle, end to end through the real claim path: a Pod is
  # minted for one job and GitHub places another on it. `record_execution/3`
  # starts the executed job itself, so the sweep is exercised by putting
  # that row back to `queued` afterwards — the state the transition left
  # behind before it existed, and the state a Pod's release still produces
  # when it was `claimed` elsewhere at the time.
  defp strand_executing!(account, claimed_job_id, executed_job_id, pod_name, runner_name) do
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, claimed_job_id))
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, executed_job_id))
    {:ok, claim} = Claims.attempt(claimed_job_id, account.id, "fleet-a", pod_name, @linux_resources)
    :ok = Claims.mark_running(claimed_job_id, runner_name, claim.claimed_at)

    {:mismatch, _displaced} = Claims.record_execution(runner_name, executed_job_id, account.id)
    :ok = WorkflowJobs.requeue(executed_job_id)

    :ok
  end

  describe "perform/1" do
    test "starts a queued row a live claim proves is executing" do
      account = account_fixture()
      strand_executing!(account, 8001, 8002, "pod-1", "runner-stuck")
      assert Repo.get!(WorkflowJob, 8002).status == "queued"

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
      assert Repo.get!(WorkflowJob, 8011).status == "queued"
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

    # The boundary the moduledoc claims. Without the `in_progress`
    # delivery no claim carries `executed_workflow_job_id`, so there is
    # no evidence to sweep on and the row waits for its completion.
    test "cannot reach a row whose in_progress delivery never landed" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 8041))
      :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 8042))
      {:ok, claim} = Claims.attempt(8041, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(8041, "runner-silent", claim.claimed_at)

      assert :ok = perform_job(UnstartedExecutionsWorker, %{})

      assert Repo.get!(WorkflowJob, 8042).status == "queued"
    end
  end
end
