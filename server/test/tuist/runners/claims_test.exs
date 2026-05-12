defmodule Tuist.Runners.ClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims

  # Accounts default to `runner_max_concurrent: 0` (runners
  # disabled). The transactional cap check inside `attempt/4`
  # rejects those as `:runners_disabled`, so every test that
  # expects a successful claim has to lift the cap explicitly.
  defp enabled_account_fixture(cap \\ 10) do
    account = account_fixture()
    {1, _} = Repo.update_all(from(a in Account, where: a.id == ^account.id), set: [runner_max_concurrent: cap])
    Repo.reload!(account)
  end

  describe "attempt/4" do
    test "claims a workflow_job and returns the claim" do
      account = enabled_account_fixture()

      assert {:ok, %Claim{} = claim} =
               Claims.attempt(1001, account.id, "fleet-a", "pod-1")

      assert claim.workflow_job_id == 1001
      assert claim.account_id == account.id
      assert claim.fleet_name == "fleet-a"
      assert claim.pod_name == "pod-1"
      assert claim.lifecycle_state == "claimed"
      assert %DateTime{} = claim.claimed_at
    end

    test "returns :lost_race on a duplicate workflow_job_id" do
      account = enabled_account_fixture()

      assert {:ok, _} = Claims.attempt(1002, account.id, "fleet-a", "pod-1")
      assert {:error, :lost_race} = Claims.attempt(1002, account.id, "fleet-a", "pod-2")
    end

    test "returns :over_cap when the account is already at runner_max_concurrent" do
      account = enabled_account_fixture(2)

      assert {:ok, _} = Claims.attempt(1100, account.id, "fleet-a", "pod-1")
      assert {:ok, _} = Claims.attempt(1101, account.id, "fleet-a", "pod-2")

      # Third attempt blows past the per-account cap (across all
      # fleets). The transactional check rejects without inserting.
      assert {:error, :over_cap} = Claims.attempt(1102, account.id, "fleet-b", "pod-3")
    end

    test "returns :runners_disabled when runner_max_concurrent is 0" do
      account = account_fixture()
      # Default cap is 0 — runners are off for the customer.
      assert {:error, :runners_disabled} = Claims.attempt(1200, account.id, "fleet-a", "pod-1")
    end

    test "returns :pod_in_use when the same pod already has a live claim" do
      account = enabled_account_fixture()

      assert {:ok, _} = Claims.attempt(1300, account.id, "fleet-a", "pod-1")

      # A customer-controlled workflow inside the VM that reads
      # /etc/tuist-sa-token and calls dispatch again must not be
      # able to claim a second job while the first is still
      # active — the live claim makes this fail-closed.
      assert {:error, :pod_in_use} = Claims.attempt(1301, account.id, "fleet-a", "pod-1")
    end

    test "returns :unknown_account when account_id has no row" do
      assert {:error, :unknown_account} = Claims.attempt(1400, 9_999_999, "fleet-a", "pod-1")
    end
  end

  describe "mark_running/2" do
    test "promotes a claimed row to running" do
      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(1500, account.id, "fleet-a", "pod-1")

      assert :ok = Claims.mark_running(1500, "runner-abc")

      row = Repo.one(from(c in Claim, where: c.workflow_job_id == ^1500))
      assert row.lifecycle_state == "running"
      assert row.runner_name == "runner-abc"
    end

    test "is a no-op when the row is gone" do
      assert :ok = Claims.mark_running(9_999_999, "runner-x")
    end
  end

  describe "release/2" do
    test "deletes a claim when (workflow_job_id, claimed_at) match" do
      account = enabled_account_fixture()
      {:ok, claim} = Claims.attempt(2001, account.id, "fleet-a", "pod-1")

      assert :ok = Claims.release(claim.workflow_job_id, claim.claimed_at)
      assert Claims.counts_per_account() == %{}
    end

    test "returns :stale_claim when claimed_at has moved on" do
      account = enabled_account_fixture()
      {:ok, _claim} = Claims.attempt(2002, account.id, "fleet-a", "pod-1")

      # Pretend the worker released and someone re-claimed with a
      # fresh handle — original serve's release shouldn't stomp.
      stale_handle = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert {:error, :stale_claim} = Claims.release(2002, stale_handle)
      # Original claim is still there.
      assert Claims.counts_per_account() == %{account.id => 1}
    end

    test "returns :stale_claim when the row is gone" do
      assert {:error, :stale_claim} = Claims.release(9_999_999, DateTime.utc_now())
    end
  end

  describe "counts_per_account/0" do
    test "returns per-account inflight counts across ALL fleets" do
      a = enabled_account_fixture()
      b = enabled_account_fixture()

      {:ok, _} = Claims.attempt(3001, a.id, "fleet-cnt", "pod-a-1")
      {:ok, _} = Claims.attempt(3002, a.id, "fleet-cnt", "pod-a-2")
      {:ok, _} = Claims.attempt(3003, b.id, "fleet-cnt", "pod-b-1")
      # Cap is account-level, so this fourth claim on a different
      # fleet must still count toward account `a`'s total.
      {:ok, _} = Claims.attempt(3004, a.id, "fleet-other", "pod-a-3")

      counts = Claims.counts_per_account()
      assert Map.get(counts, a.id) == 3
      assert Map.get(counts, b.id) == 1
    end

    test "returns empty map when nothing is in flight" do
      assert Claims.counts_per_account() == %{}
    end
  end

  describe "complete/1" do
    test "deletes the claim regardless of handle" do
      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(5001, account.id, "fleet-c", "pod-1")

      assert :ok = Claims.complete(5001)
      assert Claims.counts_per_account() == %{}
    end

    test "is idempotent for unknown workflow_job_id" do
      assert :ok = Claims.complete(9_999_999)
    end
  end

  describe "list_stale/1" do
    test "returns claimed rows older than the threshold without deleting" do
      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(4001, account.id, "fleet-stale", "pod-1")
      {:ok, _} = Claims.attempt(4002, account.id, "fleet-stale", "pod-2")

      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      stale = Claims.list_stale(future)

      assert length(stale) == 2
      ids = stale |> Enum.map(& &1.workflow_job_id) |> Enum.sort()
      assert ids == [4001, 4002]
      # Rows are still in place — the caller will release each
      # via Claims.release/2 after writing the CH transition.
      assert Claims.counts_per_account() == %{account.id => 2}
    end

    test "skips claims that already transitioned to running" do
      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(4200, account.id, "fleet-running", "pod-1")
      {:ok, _} = Claims.attempt(4201, account.id, "fleet-running", "pod-2")

      # One claim is healthy and running for hours — must NOT be
      # reaped just because it's older than the threshold, since
      # the cap slot belongs to a real GitHub runner.
      :ok = Claims.mark_running(4200, "runner-long")

      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      stale = Claims.list_stale(future)

      ids = stale |> Enum.map(& &1.workflow_job_id) |> Enum.sort()
      assert ids == [4201]
    end

    test "leaves fresh claims alone" do
      account = enabled_account_fixture()
      {:ok, _} = Claims.attempt(4101, account.id, "fleet-fresh", "pod-1")

      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert [] = Claims.list_stale(past)
      assert Claims.counts_per_account() == %{account.id => 1}
    end
  end
end
