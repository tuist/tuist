defmodule Tuist.Kura.Workers.RolloutWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, account: account, deployment: deployment, server: server}
  end

  test "activates the server when rollout succeeds", %{deployment: deployment, server: server} do
    stub(Provisioner, :rollout, fn %Server{}, inputs ->
      refute Map.has_key?(inputs, :on_log_line)
      :ok
    end)

    assert :ok =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    assert %Deployment{status: :succeeded} = Repo.get!(Deployment, deployment.id)

    server = Repo.get!(Server, server.id)
    assert server.status == :active
    assert server.current_image_tag == "0.5.2"
    assert server.url =~ ~r/^http:\/\/localhost:\d+$/
  end

  test "fails the deployment when server activation fails", %{deployment: deployment, server: server} do
    stub(Provisioner, :rollout, fn %Server{}, _inputs -> :ok end)
    stub(Kura, :activate_server, fn %Server{}, "0.5.2" -> {:error, :activation_failed} end)

    assert {:error, ":activation_failed"} =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    assert %Deployment{status: :failed, error_message: ":activation_failed"} =
             Repo.get!(Deployment, deployment.id)

    assert %Server{status: :failed} = Repo.get!(Server, server.id)
  end

  test "cancels the deployment without provisioning when the server is destroying", %{
    deployment: deployment,
    server: server
  } do
    reject(&Provisioner.rollout/2)
    {:ok, server} = Kura.destroy_server(server)

    assert :ok =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    deployment = Repo.get!(Deployment, deployment.id)
    assert deployment.status == :cancelled
    assert deployment.error_message == "server #{server.id} is destroying; skipping rollout"

    assert %Server{status: :destroying} = Repo.get!(Server, server.id)
  end

  test "does not reactivate a server destroyed while rollout was in flight", %{
    deployment: deployment,
    server: server
  } do
    stub(Provisioner, :rollout, fn %Server{}, _inputs ->
      server = Repo.get!(Server, server.id)
      {:ok, server} = Kura.destroy_server(server)
      {:ok, _server} = Kura.mark_destroyed(server)
      :ok
    end)

    assert :ok =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    assert %Deployment{status: :cancelled, error_message: message} = Repo.get!(Deployment, deployment.id)
    assert message == "server #{server.id} became destroyed during rollout; skipping activation"

    assert %Server{status: :destroyed, url: nil} = Repo.get!(Server, server.id)
  end

  test "fails the parent server when a running deployment is picked up again", %{
    deployment: deployment,
    server: server
  } do
    reject(&Provisioner.rollout/2)
    {:ok, deployment} = Kura.mark_running(deployment)

    assert :ok =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    assert %Deployment{
             status: :failed,
             error_message: "deployment was already running; re-trigger manually"
           } = Repo.get!(Deployment, deployment.id)

    assert %Server{status: :failed} = Repo.get!(Server, server.id)
  end

  test "stores the provisioner failure on the deployment", %{deployment: deployment, server: server} do
    stub(Provisioner, :rollout, fn %Server{}, _inputs -> {:error, "rollout exited with status 1"} end)

    assert {:error, "rollout exited with status 1"} =
             RolloutWorker.perform(%Oban.Job{
               args: %{"deployment_id" => deployment.id, "account_id" => server.account_id}
             })

    assert %Deployment{status: :failed, error_message: "rollout exited with status 1"} =
             Repo.get!(Deployment, deployment.id)
  end
end
