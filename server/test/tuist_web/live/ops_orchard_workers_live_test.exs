defmodule TuistWeb.OpsOrchardWorkersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.Runners
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)
    Mimic.stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    {:ok, pool} =
      Runners.create_orchard_worker_pool(%{
        account_id: user.account.id,
        name: "pool-one",
        desired_size: 2,
        scaleway_zone: "fr-par-3",
        scaleway_server_type: "M1-M",
        scaleway_os: "macos-tahoe-26.0"
      })

    %{conn: conn, user: user, pool: pool}
  end

  test "renders pools and workers sections", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/ops/orchard_workers")

    assert html =~ "Pools"
    assert html =~ "pool-one"
    assert html =~ "2 / 0"
    assert html =~ "Workers"
  end

  test "shows empty states when nothing exists", %{conn: conn, pool: pool} do
    {:ok, _} = Runners.delete_orchard_worker_pool(pool)

    {:ok, _lv, html} = live(conn, ~p"/ops/orchard_workers")

    assert html =~ "No pools yet"
    assert html =~ "No workers"
  end

  test "Reconcile button enqueues a reconcile job", %{conn: conn, pool: pool} do
    {:ok, lv, _html} = live(conn, ~p"/ops/orchard_workers")

    lv |> element("button", "Reconcile") |> render_click()

    assert_enqueued(
      worker: Tuist.Runners.Workers.ReconcilePoolsWorker,
      args: %{"orchard_worker_pool_id" => pool.id}
    )
  end

  test "Deprovision button moves worker to draining and enqueues deprovision",
       %{conn: conn, pool: pool} do
    {:ok, worker} =
      Runners.create_orchard_worker(%{
        pool_id: pool.id,
        name: "worker-a",
        scaleway_zone: pool.scaleway_zone,
        scaleway_server_type: pool.scaleway_server_type,
        scaleway_os: pool.scaleway_os
      })

    {:ok, _} = Runners.update_orchard_worker(worker, %{status: :online})

    {:ok, lv, _html} = live(conn, ~p"/ops/orchard_workers")

    lv |> element("button", "Deprovision") |> render_click()

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :draining

    assert_enqueued(
      worker: Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker,
      args: %{"orchard_worker_id" => worker.id}
    )
  end

  test "Delete record button removes terminated workers", %{conn: conn, pool: pool} do
    {:ok, worker} =
      Runners.create_orchard_worker(%{
        pool_id: pool.id,
        name: "worker-b",
        scaleway_zone: pool.scaleway_zone,
        scaleway_server_type: pool.scaleway_server_type,
        scaleway_os: pool.scaleway_os
      })

    {:ok, _} = Runners.update_orchard_worker(worker, %{status: :terminated})

    {:ok, lv, _html} = live(conn, ~p"/ops/orchard_workers")

    lv |> element("button", "Delete record") |> render_click()

    assert {:error, :not_found} = Runners.get_orchard_worker(worker.id)
  end
end
