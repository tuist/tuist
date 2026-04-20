defmodule Tuist.Runners.Workers.DeprovisionOrchardWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners
  alias Tuist.Runners.Workers.DeprovisionOrchardWorkerWorker
  alias Tuist.Scaleway
  alias Tuist.Scaleway.Client, as: ScalewayClient
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  defp create_worker(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture(preload: [:account])

    {:ok, pool} =
      Runners.create_orchard_worker_pool(%{
        account_id: user.account.id,
        name: "pool-#{System.unique_integer([:positive])}",
        scaleway_zone: "fr-par-3",
        scaleway_server_type: "M1-M",
        scaleway_os: "macos-tahoe-26.0"
      })

    base = %{
      pool_id: pool.id,
      name: "worker-deprov-#{System.unique_integer([:positive])}",
      scaleway_zone: pool.scaleway_zone,
      scaleway_server_type: pool.scaleway_server_type,
      scaleway_os: pool.scaleway_os
    }

    {:ok, worker} = Runners.create_orchard_worker(Map.merge(base, attrs))
    worker
  end

  test "deletes Scaleway server and marks worker terminated" do
    worker =
      then(create_worker(), fn w ->
        {:ok, w} =
          Runners.update_orchard_worker(w, %{
            status: :online,
            scaleway_server_id: "server-1",
            ip_address: "10.0.0.1"
          })

        w
      end)

    config = %Scaleway{secret_key: "k", project_id: "p"}

    expect(Scaleway, :config, fn -> {:ok, config} end)

    expect(ScalewayClient, :delete_server, fn ^config, "fr-par-3", "server-1" -> :ok end)

    assert :ok =
             perform_job(DeprovisionOrchardWorkerWorker, %{"orchard_worker_id" => worker.id})

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :terminated
    assert reloaded.terminated_at
  end

  test "skips Scaleway delete when there's no server id" do
    worker = create_worker()

    config = %Scaleway{secret_key: "k", project_id: "p"}
    expect(Scaleway, :config, fn -> {:ok, config} end)
    reject(&ScalewayClient.delete_server/3)

    assert :ok =
             perform_job(DeprovisionOrchardWorkerWorker, %{"orchard_worker_id" => worker.id})

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :terminated
  end
end
