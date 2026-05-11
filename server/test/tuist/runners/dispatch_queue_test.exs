defmodule Tuist.Runners.DispatchQueueTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.DispatchQueue
  alias Tuist.Runners.DispatchQueueEntry

  defp account_with_cap(cap) do
    account = account_fixture()
    {:ok, account} = Repo.update(Ecto.Changeset.change(account, runner_max_concurrent: cap))
    account
  end

  describe "enqueue/3" do
    test "refuses when runner_max_concurrent is 0" do
      account = account_with_cap(0)
      assert {:error, :runners_disabled} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
    end

    test "inserts a queue entry when account is enabled" do
      account = account_with_cap(3)
      assert {:ok, entry} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      assert entry.account_id == account.id
      assert entry.fleet_name == "fleet-a"
      assert entry.repo == "acme/cli"
      assert is_nil(entry.claimed_at)
    end
  end

  describe "claim_oldest_eligible/3" do
    test "returns :empty when queue is empty" do
      assert {:error, :empty} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
    end

    test "claims the oldest unclaimed entry for the fleet" do
      account_a = account_with_cap(2)
      account_b = account_with_cap(2)

      {:ok, _} = DispatchQueue.enqueue(account_a, "fleet-a", "acme/older")
      Process.sleep(20)
      {:ok, _} = DispatchQueue.enqueue(account_b, "fleet-a", "globex/newer")

      assert {:ok, %{account_id: claimed, repo: "acme/older"}} =
               DispatchQueue.claim_oldest_eligible("fleet-a", [])

      assert claimed == account_a.id
    end

    test "skips entries for ineligible accounts" do
      account_a = account_with_cap(2)
      account_b = account_with_cap(2)

      {:ok, _} = DispatchQueue.enqueue(account_a, "fleet-a", "acme/at-cap")
      {:ok, _} = DispatchQueue.enqueue(account_b, "fleet-a", "globex/free")

      assert {:ok, %{account_id: claimed, repo: "globex/free"}} =
               DispatchQueue.claim_oldest_eligible("fleet-a", [account_a.id])

      assert claimed == account_b.id
    end

    test "scopes by fleet" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")

      assert {:error, :empty} = DispatchQueue.claim_oldest_eligible("fleet-b", [])
    end

    test "soft-claims (row survives) with claimed_at set" do
      account = account_with_cap(2)
      {:ok, entry} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")

      {:ok, %{id: id, claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
      assert id == entry.id
      assert %DateTime{} = claimed_at

      reloaded = Repo.get!(DispatchQueueEntry, id)
      assert DateTime.compare(reloaded.claimed_at, claimed_at) == :eq

      # pending_count still includes in-flight rows (one entry,
      # claimed but not finalised).
      assert DispatchQueue.pending_count(account) == 1
    end

    test "subsequent claim skips soft-claimed rows" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/first")
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/second")

      {:ok, %{repo: "acme/first"}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      {:ok, %{repo: "acme/second"}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
    end

    test "rolls back as :over_cap when in-flight + k8s count is at cap" do
      account = account_with_cap(1)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/one")
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/two")

      # First claim succeeds (k8s_count=0, inflight=0 < cap=1).
      assert {:ok, _} = DispatchQueue.claim_oldest_eligible("fleet-a", [], %{})

      # Second claim must not exceed cap: in-flight is already 1.
      assert {:error, :over_cap} =
               DispatchQueue.claim_oldest_eligible("fleet-a", [], %{})
    end

    test "honors cap_lookup k8s count even when no inflight rows exist" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")

      # Caller reports 2 running Pods for this account; cap is 2,
      # so this claim must roll back.
      cap_lookup = %{account.id => {2, 2}}

      assert {:error, :over_cap} =
               DispatchQueue.claim_oldest_eligible("fleet-a", [], cap_lookup)
    end
  end

  describe "finalize_claim/2" do
    test "deletes the row when (id, claimed_at) match" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{id: id, claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      assert :ok = DispatchQueue.finalize_claim(id, claimed_at)
      assert DispatchQueue.pending_count(account) == 0
    end

    test "returns :stale_claim for unknown id" do
      assert {:error, :stale_claim} =
               DispatchQueue.finalize_claim(424_242, DateTime.utc_now())
    end

    test "returns :stale_claim when claimed_at no longer matches" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{id: id, claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      # Stale-claims worker releases the row, then a second poll re-claims it.
      assert 1 == DispatchQueue.release_stale_claims(DateTime.add(claimed_at, 1, :second))

      {:ok, %{id: ^id, claimed_at: new_claimed_at}} =
        DispatchQueue.claim_oldest_eligible("fleet-a", [])

      assert DateTime.compare(new_claimed_at, claimed_at) != :eq

      # Original serve's finalize with the stale handle no-ops.
      assert {:error, :stale_claim} = DispatchQueue.finalize_claim(id, claimed_at)
      # The second poll's row is still there.
      assert DispatchQueue.pending_count(account) == 1
    end
  end

  describe "release_claim/2" do
    test "nulls claimed_at so the row goes back to the pool" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{id: id, claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      assert :ok = DispatchQueue.release_claim(id, claimed_at)

      # Released row is claimable again.
      assert {:ok, %{id: ^id}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
    end

    test "is a no-op when the row is already pending" do
      account = account_with_cap(2)
      {:ok, entry} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      assert {:error, :stale_claim} = DispatchQueue.release_claim(entry.id, DateTime.utc_now())
    end

    test "returns :stale_claim when claimed_at no longer matches (worker raced + re-claim)" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{id: id, claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      assert 1 == DispatchQueue.release_stale_claims(DateTime.add(claimed_at, 1, :second))
      {:ok, %{id: ^id}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      # The original serve's release with the stale handle must
      # NOT null out the second claim's claimed_at.
      assert {:error, :stale_claim} = DispatchQueue.release_claim(id, claimed_at)
      reloaded = Repo.get!(DispatchQueueEntry, id)
      assert reloaded.claimed_at
    end
  end

  describe "release_stale_claims/1" do
    test "releases claims older than the threshold" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{id: id}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      # Backdate the claim.
      stale = DateTime.add(DateTime.utc_now(), -3600, :second)

      {1, _} = Repo.update_all(from(q in DispatchQueueEntry, where: q.id == ^id), set: [claimed_at: stale])

      released = DispatchQueue.release_stale_claims(DateTime.utc_now())
      assert released == 1

      assert {:ok, %{id: ^id}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
    end

    test "does not release fresh claims" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      {:ok, %{claimed_at: claimed_at}} = DispatchQueue.claim_oldest_eligible("fleet-a", [])

      threshold = DateTime.add(claimed_at, -1, :second)
      released = DispatchQueue.release_stale_claims(threshold)
      assert released == 0
    end
  end
end
