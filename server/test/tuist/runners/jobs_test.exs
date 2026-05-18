defmodule Tuist.Runners.JobsTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

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

  describe "enqueue/1" do
    test "inserts a queued row" do
      account = account_fixture()
      assert :ok = enqueue_fixture(account, 1001)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "idempotent on workflow_job_id (re-enqueue collapses via RMT)" do
      account = account_fixture()
      assert :ok = enqueue_fixture(account, 1002)
      assert :ok = enqueue_fixture(account, 1002)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end
  end

  describe "pick_queued/2" do
    test "returns :empty when no queued work" do
      assert {:error, :empty} = Jobs.pick_queued("fleet-empty", [])
    end

    test "returns the oldest queued workflow_job for the fleet" do
      account_a = account_fixture()
      account_b = account_fixture()

      :ok = enqueue_fixture(account_a, 2001, fleet: "fleet-x", repo: "acme/older")
      Process.sleep(20)
      :ok = enqueue_fixture(account_b, 2002, fleet: "fleet-x", repo: "globex/newer")

      assert {:ok, %{workflow_job_id: 2001, account_id: a_id}} =
               Jobs.pick_queued("fleet-x", [])

      assert a_id == account_a.id
    end

    test "skips ineligible accounts" do
      a = account_fixture()
      b = account_fixture()

      :ok = enqueue_fixture(a, 3001, fleet: "fleet-cap", repo: "a/at-cap")
      :ok = enqueue_fixture(b, 3002, fleet: "fleet-cap", repo: "b/free")

      assert {:ok, %{workflow_job_id: 3002}} = Jobs.pick_queued("fleet-cap", [a.id])
    end
  end

  describe "record_claimed/3" do
    test "transitions queued → claimed visible in CH" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 5001, fleet: "fleet-s")
      {:ok, candidate} = Jobs.pick_queued("fleet-s", [])

      assert :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "claimed", 0) == 1
      assert Map.get(counts, "queued", 0) == 0
    end
  end

  describe "record_running/2" do
    test "transitions to running with runner_name set" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 5101, fleet: "fleet-r")
      {:ok, candidate} = Jobs.pick_queued("fleet-r", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert :ok = Jobs.record_running(5101, "tuist-runner-x")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "running", 0) == 1
      assert Map.get(counts, "claimed", 0) == 0
    end
  end

  describe "record_queued/1" do
    test "re-surfaces a claimed row as queued (after release/stale)" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 6001, fleet: "fleet-q")
      {:ok, candidate} = Jobs.pick_queued("fleet-q", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert :ok = Jobs.record_queued(6001)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
      assert Map.get(counts, "claimed", 0) == 0
    end
  end

  describe "list_for_account/2" do
    test "returns jobs for the given account, latest first" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 8001, repo: "acme/a")
      Process.sleep(20)
      :ok = enqueue_fixture(account, 8002, repo: "acme/b")
      :ok = enqueue_fixture(other, 8003, repo: "globex/c")

      jobs = Jobs.list_for_account(account.id)

      assert Enum.map(jobs, & &1.workflow_job_id) == [8002, 8001]
      assert Enum.all?(jobs, &(&1.account_id == account.id))
    end

    test "filters by status when provided" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8101, fleet: "fleet-l")
      :ok = enqueue_fixture(account, 8102, fleet: "fleet-l")
      {:ok, candidate} = Jobs.pick_queued("fleet-l", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      queued = Jobs.list_for_account(account.id, status: "queued")
      claimed = Jobs.list_for_account(account.id, status: "claimed")

      assert queued |> Enum.map(& &1.workflow_job_id) |> Enum.sort() == [8102]
      assert claimed |> Enum.map(& &1.workflow_job_id) |> Enum.sort() == [8101]
    end

    test "respects the limit option" do
      account = account_fixture()

      Enum.each(1..3, fn i ->
        :ok = enqueue_fixture(account, 8200 + i)
      end)

      assert length(Jobs.list_for_account(account.id, limit: 2)) == 2
    end
  end

  describe "get_for_account/2" do
    test "returns the merged row for the given workflow_job" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 9001, repo: "acme/x")

      assert {:ok, %{workflow_job_id: 9001, repo: "acme/x"}} =
               Jobs.get_for_account(account.id, 9001)
    end

    test "returns :not_found when the job belongs to another account" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 9101)

      assert {:error, :not_found} = Jobs.get_for_account(other.id, 9101)
    end

    test "returns :not_found when the workflow_job_id doesn't exist" do
      account = account_fixture()
      assert {:error, :not_found} = Jobs.get_for_account(account.id, 99_999_999)
    end
  end

  describe "complete/2" do
    test "transitions to completed with the conclusion" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 7001, fleet: "fleet-c")
      {:ok, candidate} = Jobs.pick_queued("fleet-c", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(7001, "runner-x")

      assert {:ok, %{status: "completed", conclusion: "success"}} =
               Jobs.complete(7001, "success")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "completed", 0) == 1
    end

    test "returns :not_found for an unknown workflow_job_id" do
      assert {:error, :not_found} = Jobs.complete(9_999_999, "success")
    end
  end
end
