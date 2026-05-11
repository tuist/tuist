defmodule Tuist.Runners.PoolsTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Pool
  alias Tuist.Runners.Pools

  describe "create_pool/1 — customer" do
    test "inserts a customer pool with the required fields" do
      account = account_fixture()

      assert {:ok, %Pool{} = pool} =
               Pools.create_pool(%{
                 name: "acme",
                 role: "customer",
                 account_id: account.id,
                 owner: "acme",
                 labels: ["self-hosted", "macOS", "tuist-acme-macos"],
                 max_concurrent: 5
               })

      assert pool.name == "acme"
      assert pool.role == "customer"
      assert pool.account_id == account.id
      assert pool.max_concurrent == 5
    end

    test "max_concurrent is optional (nil = no cap)" do
      account = account_fixture()

      assert {:ok, %Pool{max_concurrent: nil}} =
               Pools.create_pool(%{
                 name: "acme",
                 role: "customer",
                 account_id: account.id,
                 owner: "acme",
                 labels: ["tuist-acme-macos"]
               })
    end

    test "rejects a customer pool missing account_id / owner / labels" do
      assert {:error, changeset} =
               Pools.create_pool(%{name: "acme", role: "customer"})

      errors = errors_on(changeset)
      assert errors[:account_id]
      assert errors[:owner]
      assert errors[:labels]
    end

    test "rejects non-positive max_concurrent" do
      account = account_fixture()

      assert {:error, changeset} =
               Pools.create_pool(%{
                 name: "acme",
                 role: "customer",
                 account_id: account.id,
                 owner: "acme",
                 labels: ["tuist-acme-macos"],
                 max_concurrent: 0
               })

      assert errors_on(changeset)[:max_concurrent]
    end

    test "rejects duplicate name" do
      account = account_fixture()

      attrs = %{
        name: "acme",
        role: "customer",
        account_id: account.id,
        owner: "acme",
        labels: ["tuist-acme-macos"]
      }

      assert {:ok, _} = Pools.create_pool(attrs)
      assert {:error, changeset} = Pools.create_pool(attrs)
      assert errors_on(changeset)[:name]
    end
  end

  describe "create_pool/1 — shared_warm" do
    test "inserts a shared_warm pool with no account / owner / labels" do
      assert {:ok, %Pool{} = pool} =
               Pools.create_pool(%{name: "warm-standby", role: "shared_warm"})

      assert pool.role == "shared_warm"
      assert pool.account_id == nil
      assert pool.owner == ""
      assert pool.labels == []
      assert pool.max_concurrent == nil
    end

    test "rejects a shared_warm pool that carries account_id, owner, or max_concurrent" do
      account = account_fixture()

      assert {:error, changeset} =
               Pools.create_pool(%{
                 name: "warm-standby",
                 role: "shared_warm",
                 account_id: account.id,
                 owner: "tuist",
                 max_concurrent: 10
               })

      errors = errors_on(changeset)
      assert errors[:account_id]
      assert errors[:owner]
      assert errors[:max_concurrent]
    end

    test "enforces at most one shared_warm pool per cluster" do
      assert {:ok, _} = Pools.create_pool(%{name: "warm-1", role: "shared_warm"})

      assert {:error, changeset} =
               Pools.create_pool(%{name: "warm-2", role: "shared_warm"})

      assert errors_on(changeset)[:role]
    end
  end

  describe "find_shared_warm/0" do
    test "returns nil when no shared_warm row is present" do
      assert Pools.find_shared_warm() == nil
    end

    test "returns the shared_warm row when one exists" do
      {:ok, pool} = Pools.create_pool(%{name: "warm-standby", role: "shared_warm"})
      assert %Pool{name: "warm-standby"} = Pools.find_shared_warm()
      assert Pools.find_shared_warm().id == pool.id
    end
  end
end
