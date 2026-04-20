defmodule Tuist.Runners.ReconcilerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners
  alias Tuist.Runners.Reconciler
  alias Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker
  alias Tuist.Runners.Workers.ProvisionOrchardWorkerWorker
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

  describe "reconcile/1 — scale up" do
    test "creates missing workers and enqueues provision jobs" do
      pool = create_pool(%{desired_size: 3})

      assert {:ok, %{action: :scaled_up, created: created}} = Reconciler.reconcile(pool.id)
      assert length(created) == 3

      workers = Runners.list_active_workers_in_pool(pool.id)
      assert length(workers) == 3

      Enum.each(created, fn id ->
        assert_enqueued(worker: ProvisionOrchardWorkerWorker, args: %{"orchard_worker_id" => id})
      end)
    end

    test "updates last_reconciled_at" do
      pool = create_pool(%{desired_size: 1})
      Reconciler.reconcile(pool.id)
      {:ok, reloaded} = Runners.get_orchard_worker_pool(pool.id)
      assert reloaded.last_reconciled_at
    end
  end

  describe "reconcile/1 — scale down" do
    test "drains oldest queued workers first and enqueues deprovision" do
      pool = create_pool(%{desired_size: 3})
      {:ok, _} = Reconciler.reconcile(pool.id)

      {:ok, _} = Runners.update_orchard_worker_pool_spec(pool, %{desired_size: 1})
      {:ok, result} = Reconciler.reconcile(pool.id)

      assert result.action == :scaled_down
      assert length(result.drained) == 2

      Enum.each(result.drained, fn id ->
        {:ok, worker} = Runners.get_orchard_worker(id)
        assert worker.status == :draining

        assert_enqueued(
          worker: DeprovisionOrchardWorkerWorker,
          args: %{"orchard_worker_id" => id}
        )
      end)
    end
  end

  describe "reconcile/1 — steady state" do
    test "is a no-op when current == desired" do
      pool = create_pool(%{desired_size: 2})
      {:ok, _} = Reconciler.reconcile(pool.id)
      {:ok, result} = Reconciler.reconcile(pool.id)
      assert result.action == :steady
      assert result.size == 2
    end
  end

  describe "reconcile/1 — disabled pool" do
    test "drains all active workers" do
      pool = create_pool(%{desired_size: 2})
      {:ok, _} = Reconciler.reconcile(pool.id)

      {:ok, _} = Runners.update_orchard_worker_pool_spec(pool, %{enabled: false})
      {:ok, result} = Reconciler.reconcile(pool.id)

      assert result.action == :disabled
      assert length(result.drained) == 2
    end
  end

  describe "reconcile_all/0" do
    test "reconciles every enabled pool" do
      a = create_pool(%{desired_size: 1})
      _disabled = create_pool(%{desired_size: 5, enabled: false})
      b = create_pool(%{desired_size: 2})

      results = Reconciler.reconcile_all()
      reconciled_ids = Enum.map(results, fn {id, _} -> id end)

      assert a.id in reconciled_ids
      assert b.id in reconciled_ids
    end
  end
end
