defmodule Tuist.RunnersOrchardWorkersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners
  alias Tuist.Runners.OrchardWorker
  alias Tuist.Runners.OrchardWorkerPool
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp create_pool(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture(preload: [:account])

    base = %{
      account_id: user.account.id,
      name: "pool-#{System.unique_integer([:positive])}",
      desired_size: 0,
      scaleway_zone: "fr-par-3",
      scaleway_server_type: "M1-M",
      scaleway_os: "macos-tahoe-26.0"
    }

    {:ok, pool} = Runners.create_orchard_worker_pool(Map.merge(base, attrs))
    pool
  end

  describe "create_orchard_worker_pool/1" do
    test "creates a pool with spec fields" do
      pool = create_pool(%{desired_size: 2})
      assert %OrchardWorkerPool{desired_size: 2, enabled: true} = pool
    end

    test "rejects invalid names" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      assert {:error, changeset} =
               Runners.create_orchard_worker_pool(%{
                 account_id: user.account.id,
                 name: "BadName",
                 scaleway_zone: "fr-par-3",
                 scaleway_server_type: "M1-M",
                 scaleway_os: "macos-tahoe-26.0"
               })

      assert %{name: [_]} = errors_on(changeset)
    end

    test "enforces (account_id, name) uniqueness" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      base = %{
        account_id: user.account.id,
        name: "shared-name",
        scaleway_zone: "fr-par-3",
        scaleway_server_type: "M1-M",
        scaleway_os: "macos-tahoe-26.0"
      }

      {:ok, _} = Runners.create_orchard_worker_pool(base)

      assert {:error, changeset} = Runners.create_orchard_worker_pool(base)
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_orchard_worker_pool_spec/2" do
    test "changes desired_size" do
      pool = create_pool(%{desired_size: 0})

      assert {:ok, %OrchardWorkerPool{desired_size: 3}} =
               Runners.update_orchard_worker_pool_spec(pool, %{desired_size: 3})
    end
  end

  describe "orchard worker CRUD scoped to a pool" do
    test "create_orchard_worker requires a pool_id" do
      pool = create_pool()

      assert {:ok, %OrchardWorker{pool_id: pool_id, status: :queued}} =
               Runners.create_orchard_worker(%{
                 pool_id: pool.id,
                 name: "worker-abc",
                 scaleway_zone: pool.scaleway_zone,
                 scaleway_server_type: pool.scaleway_server_type,
                 scaleway_os: pool.scaleway_os
               })

      assert pool_id == pool.id
    end

    test "list_active_workers_in_pool excludes terminated workers" do
      pool = create_pool()

      {:ok, active} =
        Runners.create_orchard_worker(%{
          pool_id: pool.id,
          name: "active-1",
          scaleway_zone: pool.scaleway_zone,
          scaleway_server_type: pool.scaleway_server_type,
          scaleway_os: pool.scaleway_os
        })

      {:ok, terminated} =
        Runners.create_orchard_worker(%{
          pool_id: pool.id,
          name: "terminated-1",
          scaleway_zone: pool.scaleway_zone,
          scaleway_server_type: pool.scaleway_server_type,
          scaleway_os: pool.scaleway_os
        })

      {:ok, _} = Runners.update_orchard_worker(terminated, %{status: :terminated})

      workers = Runners.list_active_workers_in_pool(pool.id)
      assert Enum.map(workers, & &1.id) == [active.id]
    end
  end
end
