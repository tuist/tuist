defmodule Tuist.Runners.Workers.ProvisionOrchardWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners
  alias Tuist.Runners.OrchardWorkerProvisioner
  alias Tuist.Runners.Workers.ProvisionOrchardWorkerWorker
  alias Tuist.Scaleway
  alias Tuist.Scaleway.Client, as: ScalewayClient
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  defp create_worker do
    user = AccountsFixtures.user_fixture(preload: [:account])

    {:ok, pool} =
      Runners.create_orchard_worker_pool(%{
        account_id: user.account.id,
        name: "pool-#{System.unique_integer([:positive])}",
        scaleway_zone: "fr-par-3",
        scaleway_server_type: "M1-M",
        scaleway_os: "macos-tahoe-26.0"
      })

    Runners.create_orchard_worker(%{
      pool_id: pool.id,
      name: "worker-#{System.unique_integer([:positive])}",
      scaleway_zone: pool.scaleway_zone,
      scaleway_server_type: pool.scaleway_server_type,
      scaleway_os: pool.scaleway_os
    })
  end

  test "marks worker online after Scaleway create + provisioner succeed" do
    {:ok, worker} = create_worker()

    config = %Scaleway{secret_key: "k", project_id: "p"}

    expect(Scaleway, :config, fn -> {:ok, config} end)
    expect(ScalewayClient, :find_os_id, fn ^config, "fr-par-3", "macos-tahoe-26.0" -> {:ok, "os-uuid"} end)

    expect(ScalewayClient, :create_server, fn ^config, attrs ->
      assert attrs.zone == "fr-par-3"
      assert attrs.server_type == "M1-M"
      assert attrs.os_id == "os-uuid"

      {:ok,
       %{
         "id" => "server-1",
         "ip" => "10.0.0.1",
         "ssh_username" => "m1",
         "sudo_password" => "hunter2"
       }}
    end)

    expect(OrchardWorkerProvisioner, :provision, fn %{
                                                      ip: "10.0.0.1",
                                                      ssh_user: "m1",
                                                      sudo_password: "hunter2"
                                                    } ->
      :ok
    end)

    assert :ok =
             perform_job(ProvisionOrchardWorkerWorker, %{"orchard_worker_id" => worker.id})

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :online
    assert reloaded.scaleway_server_id == "server-1"
    assert reloaded.ip_address == "10.0.0.1"
    assert reloaded.provisioned_at
  end

  test "marks worker failed when Scaleway create fails" do
    {:ok, worker} = create_worker()
    config = %Scaleway{secret_key: "k", project_id: "p"}

    expect(Scaleway, :config, fn -> {:ok, config} end)
    expect(ScalewayClient, :find_os_id, fn _, _, _ -> {:ok, "os-uuid"} end)
    expect(ScalewayClient, :create_server, fn _, _ -> {:error, "scaleway is down"} end)

    assert {:error, "scaleway is down"} =
             perform_job(ProvisionOrchardWorkerWorker, %{"orchard_worker_id" => worker.id})

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :failed
    assert reloaded.error_message =~ "scaleway is down"
  end

  test "marks worker failed when provisioner fails" do
    {:ok, worker} = create_worker()
    config = %Scaleway{secret_key: "k", project_id: "p"}

    expect(Scaleway, :config, fn -> {:ok, config} end)
    expect(ScalewayClient, :find_os_id, fn _, _, _ -> {:ok, "os-uuid"} end)

    expect(ScalewayClient, :create_server, fn _, _ ->
      {:ok, %{"id" => "server-1", "ip" => "10.0.0.1", "ssh_username" => "m1", "sudo_password" => "p"}}
    end)

    expect(OrchardWorkerProvisioner, :provision, fn _ -> {:error, :ssh_unavailable} end)

    assert {:error, :ssh_unavailable} =
             perform_job(ProvisionOrchardWorkerWorker, %{"orchard_worker_id" => worker.id})

    {:ok, reloaded} = Runners.get_orchard_worker(worker.id)
    assert reloaded.status == :failed
  end
end
