defmodule Tuist.Runners.DispatchQueueTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.DispatchQueue

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
    end

    test "refuses when account's queue depth hits 4× max_concurrent" do
      account = account_with_cap(2)
      Enum.each(1..8, fn _ -> DispatchQueue.enqueue(account, "fleet-a", "acme/cli") end)
      assert {:error, :queue_full} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
    end
  end

  describe "claim_oldest_eligible/2" do
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

    test "removes the row on successful claim" do
      account = account_with_cap(2)
      {:ok, _} = DispatchQueue.enqueue(account, "fleet-a", "acme/cli")
      assert DispatchQueue.pending_count(account) == 1

      {:ok, _} = DispatchQueue.claim_oldest_eligible("fleet-a", [])
      assert DispatchQueue.pending_count(account) == 0
    end
  end
end
