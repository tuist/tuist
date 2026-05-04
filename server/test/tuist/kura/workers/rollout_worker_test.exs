defmodule Tuist.Kura.Workers.RolloutWorkerTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_global

  setup do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local",
        spec: :small,
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, account: account, deployment: deployment, server: server}
  end

  test "activates the server when rollout succeeds", %{deployment: deployment, server: server} do
    stub(Provisioner, :rollout, fn %Server{}, _inputs -> :ok end)

    assert :ok = RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})

    assert %Deployment{status: :succeeded} = Repo.get!(Deployment, deployment.id)

    server = Repo.get!(Server, server.id)
    assert server.status == :active
    assert server.current_image_tag == "0.5.2"
    assert server.url =~ ~r/^http:\/\/localhost:\d+$/
  end

  test "cancels the deployment without provisioning when the server is destroying", %{
    deployment: deployment,
    server: server
  } do
    reject(&Provisioner.rollout/2)
    {:ok, server} = Kura.destroy_server(server)

    assert :ok = RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})

    deployment = Repo.get!(Deployment, deployment.id)
    assert deployment.status == :cancelled
    assert deployment.error_message == "server #{server.id} is destroying; skipping rollout"

    assert [%{sequence: 1, stream: :stderr, line: line}] = Kura.list_log_lines(deployment.id)
    assert line == deployment.error_message

    assert %Server{status: :destroying} = Repo.get!(Server, server.id)
  end

  test "fails the parent server when a running deployment is picked up again", %{
    deployment: deployment,
    server: server
  } do
    reject(&Provisioner.rollout/2)
    {:ok, deployment} = Kura.mark_running(deployment)

    assert :ok = RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})

    assert %Deployment{
             status: :failed,
             error_message: "deployment was already running; re-trigger manually"
           } = Repo.get!(Deployment, deployment.id)

    assert %Server{status: :failed} = Repo.get!(Server, server.id)
  end

  test "continues log sequence when failing an already-running deployment", %{deployment: deployment} do
    reject(&Provisioner.rollout/2)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _} = Kura.append_log_lines(deployment.id, [{1, :stdout, "already emitted"}])

    assert :ok = RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})

    assert [
             %{sequence: 1, stream: :stdout, line: "already emitted"},
             %{sequence: 2, stream: :stderr, line: "deployment was already running; re-trigger manually"}
           ] =
             deployment.id
             |> Kura.list_log_lines()
             |> Enum.map(&Map.take(&1, [:sequence, :stream, :line]))
  end

  test "appends the synthetic failure line after streamed output without reusing sequence ids", %{deployment: deployment} do
    stub(Provisioner, :rollout, fn %Server{}, %{on_log_line: on_log_line} ->
      on_log_line.("starting rollout", :stdout)
      on_log_line.("still working", :stderr)
      {:error, "rollout exited with status 1"}
    end)

    assert {:error, "rollout exited with status 1"} =
             RolloutWorker.perform(%Oban.Job{args: %{"deployment_id" => deployment.id}})

    assert %Deployment{status: :failed, error_message: "rollout exited with status 1"} =
             Repo.get!(Deployment, deployment.id)

    assert [
             %{sequence: 1, stream: :stdout, line: "starting rollout"},
             %{sequence: 2, stream: :stderr, line: "still working"},
             %{sequence: 3, stream: :stderr, line: "rollout exited with status 1"}
           ] =
             deployment.id
             |> Kura.list_log_lines()
             |> Enum.map(&Map.take(&1, [:sequence, :stream, :line]))
  end
end
