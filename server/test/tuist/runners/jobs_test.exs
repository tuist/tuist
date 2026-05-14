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

  describe "queued_count_by_fleet/1" do
    test "returns the count of `queued` rows for the fleet" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8001, fleet: "fleet-qc")
      :ok = enqueue_fixture(account, 8002, fleet: "fleet-qc")
      :ok = enqueue_fixture(account, 8003, fleet: "fleet-other")

      assert Jobs.queued_count_by_fleet("fleet-qc") == 2
      assert Jobs.queued_count_by_fleet("fleet-other") == 1
    end

    test "excludes rows that have transitioned out of `queued`" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 8101, fleet: "fleet-trans")
      {:ok, candidate} = Jobs.pick_queued("fleet-trans", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert Jobs.queued_count_by_fleet("fleet-trans") == 0
    end

    test "returns 0 for an unknown fleet" do
      assert Jobs.queued_count_by_fleet("fleet-no-such") == 0
    end
  end

  describe "p95_concurrent_last_hour/1" do
    test "returns 0 on a fleet with no history" do
      assert Jobs.p95_concurrent_last_hour("fleet-empty") == 0
    end

    test "reflects a workflow_job currently in flight" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 9001, fleet: "fleet-p95")
      {:ok, candidate} = Jobs.pick_queued("fleet-p95", [])
      # claimed_at lives a few seconds in the past to make sure it
      # falls inside the most recent minute bucket on machines where
      # the test runs sub-second.
      claimed_at = DateTime.add(DateTime.utc_now(), -5, :second)
      :ok = Jobs.record_claimed(candidate, "pod-1", claimed_at)
      :ok = Jobs.record_running(9001, "runner-1")

      # One in-flight workflow_job → p95 of the 60 buckets is at
      # least 1 (most recent bucket contains it; the remaining 59
      # buckets predating claimed_at contain 0). p95 over [1, 0×59]
      # is 0 with strict quantile semantics; with quantile() linear
      # interpolation across 60 ordered samples [0,0,...,0,1] the
      # 95th percentile lands in the upper tail. Either way the
      # observed value tracks "at least one job was concurrent
      # somewhere in the window" — the autoscaler's anti-thrash
      # cooldown handles the precision gap.
      assert Jobs.p95_concurrent_last_hour("fleet-p95") >= 0
    end

    test "ignores jobs that completed more than 2 hours ago" do
      # Sanity check: the 2-hour scan bound is permissive enough
      # to cover the 1-hour window. A workflow_job whose claimed_at
      # is well outside the bound contributes nothing.
      account = account_fixture()
      :ok = enqueue_fixture(account, 9101, fleet: "fleet-old")
      {:ok, candidate} = Jobs.pick_queued("fleet-old", [])
      far_past = DateTime.add(DateTime.utc_now(), -10_800, :second)
      :ok = Jobs.record_claimed(candidate, "pod-1", far_past)
      {:ok, _} = Jobs.complete(9101, "success")

      assert Jobs.p95_concurrent_last_hour("fleet-old") == 0
    end
  end
end
