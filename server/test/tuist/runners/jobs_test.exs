defmodule Tuist.Runners.JobsTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Job
  alias Tuist.Runners.Jobs

  defp enqueue_fixture(account, workflow_job_id, opts \\ []) do
    fleet = Keyword.get(opts, :fleet, "fleet-a")
    repo = Keyword.get(opts, :repo, "acme/cli")

    Jobs.enqueue(%{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: fleet,
      repo: repo,
      workflow_run_id: workflow_job_id * 10,
      run_attempt: 1,
      job_name: "build",
      head_branch: "main",
      head_sha: "deadbeef"
    })
  end

  defp account_with_cap(cap) do
    account = account_fixture()
    {:ok, account} = Tuist.Repo.update(Ecto.Changeset.change(account, runner_max_concurrent: cap))
    account
  end

  describe "enqueue/1" do
    test "inserts a queued row" do
      account = account_with_cap(2)
      assert :ok = enqueue_fixture(account, 1001)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "idempotent on workflow_job_id (re-enqueue collapses via RMT)" do
      account = account_with_cap(2)
      assert :ok = enqueue_fixture(account, 1002)
      assert :ok = enqueue_fixture(account, 1002)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end
  end

  describe "claim/3" do
    test "returns :empty when no queued work" do
      assert {:error, :empty} = Jobs.claim("fleet-empty", "pod-1", %{})
    end

    test "claims the oldest queued workflow_job for the fleet" do
      account_a = account_with_cap(2)
      account_b = account_with_cap(2)

      :ok = enqueue_fixture(account_a, 2001, fleet: "fleet-x", repo: "acme/older")
      Process.sleep(20)
      :ok = enqueue_fixture(account_b, 2002, fleet: "fleet-x", repo: "globex/newer")

      assert {:ok, %Job{workflow_job_id: 2001, status: "claimed", pod_name: "pod-1"}} =
               Jobs.claim("fleet-x", "pod-1", %{})
    end

    test "skips accounts at cap" do
      a = account_with_cap(1)
      b = account_with_cap(1)

      :ok = enqueue_fixture(a, 3001, fleet: "fleet-cap", repo: "a/at-cap")
      :ok = enqueue_fixture(b, 3002, fleet: "fleet-cap", repo: "b/free")

      cap_lookup = %{a.id => %{cap: 1, inflight: 1}}

      assert {:ok, %Job{workflow_job_id: 3002}} =
               Jobs.claim("fleet-cap", "pod-1", cap_lookup)
    end

    test "subsequent claim picks the next queued row" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 4001, fleet: "fleet-q", repo: "acme/first")
      Process.sleep(20)
      :ok = enqueue_fixture(account, 4002, fleet: "fleet-q", repo: "acme/second")

      assert {:ok, %Job{workflow_job_id: 4001}} = Jobs.claim("fleet-q", "pod-1", %{})
      assert {:ok, %Job{workflow_job_id: 4002}} = Jobs.claim("fleet-q", "pod-2", %{})
    end
  end

  describe "start/2" do
    test "transitions claimed → running with runner_name set" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 5001, fleet: "fleet-s")
      {:ok, job} = Jobs.claim("fleet-s", "pod-1", %{})

      assert :ok = Jobs.start(job, "tuist-runner-x")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "running", 0) == 1
      assert Map.get(counts, "queued", 0) == 0
      assert Map.get(counts, "claimed", 0) == 0
    end
  end

  describe "release/1" do
    test "moves a claimed row back to queued" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 6001, fleet: "fleet-r")
      {:ok, job} = Jobs.claim("fleet-r", "pod-1", %{})

      assert :ok = Jobs.release(job)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
      assert Map.get(counts, "claimed", 0) == 0
    end

    test "is a no-op when the row has moved past our handle" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 6101, fleet: "fleet-r2")
      {:ok, job} = Jobs.claim("fleet-r2", "pod-1", %{})

      # Transition the row past claimed.
      :ok = Jobs.start(job, "runner-x")

      # Stale release should not regress the running state.
      assert :ok = Jobs.release(job)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "running", 0) == 1
      assert Map.get(counts, "queued", 0) == 0
    end
  end

  describe "complete/2" do
    test "transitions a job to completed" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 7001, fleet: "fleet-c")
      {:ok, job} = Jobs.claim("fleet-c", "pod-1", %{})
      :ok = Jobs.start(job, "runner-x")

      assert {:ok, %Job{status: "completed", conclusion: "success"}} =
               Jobs.complete(7001, "success")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "completed", 0) == 1
    end

    test "returns :not_found for an unknown workflow_job_id" do
      assert {:error, :not_found} = Jobs.complete(9_999_999, "success")
    end
  end

  describe "counts_per_account/1" do
    test "returns %{account_id => inflight} for active rows" do
      a = account_with_cap(3)
      b = account_with_cap(3)

      :ok = enqueue_fixture(a, 8001, fleet: "fleet-cnt")
      :ok = enqueue_fixture(a, 8002, fleet: "fleet-cnt")
      :ok = enqueue_fixture(b, 8003, fleet: "fleet-cnt")

      {:ok, j1} = Jobs.claim("fleet-cnt", "pod-1", %{})
      {:ok, _j2} = Jobs.claim("fleet-cnt", "pod-2", %{})
      :ok = Jobs.start(j1, "runner-1")

      counts = Jobs.counts_per_account("fleet-cnt")
      assert Map.get(counts, a.id, 0) == 2
      assert Map.get(counts, b.id, 0) == 0
    end
  end

  describe "stale_claimed/1" do
    test "returns claimed rows older than the threshold" do
      account = account_with_cap(2)
      :ok = enqueue_fixture(account, 9001, fleet: "fleet-stale")
      {:ok, _job} = Jobs.claim("fleet-stale", "pod-1", %{})

      # All current claims are fresh — nothing stale.
      assert [] = Jobs.stale_claimed(DateTime.add(DateTime.utc_now(), -3600, :second))

      # Anything from the future is stale.
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      stale = Jobs.stale_claimed(future)
      assert length(stale) == 1
      assert hd(stale).workflow_job_id == 9001
    end
  end
end
