defmodule Tuist.Runners.ClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims

  describe "attempt/4" do
    test "claims a workflow_job and returns the claim" do
      account = account_fixture()

      assert {:ok, %Claim{} = claim} =
               Claims.attempt(1001, account.id, "fleet-a", "pod-1")

      assert claim.workflow_job_id == 1001
      assert claim.account_id == account.id
      assert claim.fleet_name == "fleet-a"
      assert claim.pod_name == "pod-1"
      assert %DateTime{} = claim.claimed_at
    end

    test "returns :lost_race on a duplicate workflow_job_id" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(1002, account.id, "fleet-a", "pod-1")
      assert {:error, :lost_race} = Claims.attempt(1002, account.id, "fleet-a", "pod-2")
    end
  end

  describe "release/2" do
    test "deletes a claim when (workflow_job_id, claimed_at) match" do
      account = account_fixture()
      {:ok, claim} = Claims.attempt(2001, account.id, "fleet-a", "pod-1")

      assert :ok = Claims.release(claim.workflow_job_id, claim.claimed_at)
      assert Claims.counts_per_account("fleet-a") == %{}
    end

    test "returns :stale_claim when claimed_at has moved on" do
      account = account_fixture()
      {:ok, _claim} = Claims.attempt(2002, account.id, "fleet-a", "pod-1")

      # Pretend the worker released and someone re-claimed with a
      # fresh handle — original serve's release shouldn't stomp.
      stale_handle = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert {:error, :stale_claim} = Claims.release(2002, stale_handle)
      # Original claim is still there.
      assert Claims.counts_per_account("fleet-a") == %{account.id => 1}
    end

    test "returns :stale_claim when the row is gone" do
      assert {:error, :stale_claim} = Claims.release(9_999_999, DateTime.utc_now())
    end
  end

  describe "counts_per_account/1" do
    test "returns per-account inflight counts on a fleet" do
      a = account_fixture()
      b = account_fixture()

      {:ok, _} = Claims.attempt(3001, a.id, "fleet-cnt", "pod-1")
      {:ok, _} = Claims.attempt(3002, a.id, "fleet-cnt", "pod-2")
      {:ok, _} = Claims.attempt(3003, b.id, "fleet-cnt", "pod-3")
      {:ok, _} = Claims.attempt(3004, a.id, "fleet-other", "pod-4")

      counts = Claims.counts_per_account("fleet-cnt")
      assert Map.get(counts, a.id) == 2
      assert Map.get(counts, b.id) == 1

      other = Claims.counts_per_account("fleet-other")
      assert Map.get(other, a.id) == 1
    end

    test "returns empty map when nothing is in flight" do
      assert Claims.counts_per_account("fleet-empty") == %{}
    end
  end

  describe "complete/1" do
    test "deletes the claim regardless of handle" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(5001, account.id, "fleet-c", "pod-1")

      assert :ok = Claims.complete(5001)
      assert Claims.counts_per_account("fleet-c") == %{}
    end

    test "is idempotent for unknown workflow_job_id" do
      assert :ok = Claims.complete(9_999_999)
    end
  end

  describe "release_stale/1" do
    test "deletes claims older than the threshold and returns them" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(4001, account.id, "fleet-stale", "pod-1")
      {:ok, _} = Claims.attempt(4002, account.id, "fleet-stale", "pod-2")

      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      released = Claims.release_stale(future)

      assert length(released) == 2
      ids = released |> Enum.map(& &1.workflow_job_id) |> Enum.sort()
      assert ids == [4001, 4002]
      assert Claims.counts_per_account("fleet-stale") == %{}
    end

    test "leaves fresh claims alone" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(4101, account.id, "fleet-fresh", "pod-1")

      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert [] = Claims.release_stale(past)
      assert Claims.counts_per_account("fleet-fresh") == %{account.id => 1}
    end
  end
end
