defmodule Tuist.Kura.ReconcilerTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @orphan_message "deployment was interrupted by a server restart; re-trigger manually"

  defp running_deployment do
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
    {:ok, deployment} = Kura.mark_running(deployment)
    {server, deployment}
  end

  defp set_oban_state(deployment, state) do
    job = Repo.get!(Oban.Job, deployment.oban_job_id)
    job |> Ecto.Changeset.change(%{state: state}) |> Repo.update!()
  end

  test "fails deployments whose oban job is in a terminal state" do
    {server, deployment} = running_deployment()
    set_oban_state(deployment, "discarded")

    Reconciler.reconcile()

    assert %Deployment{status: :failed, error_message: @orphan_message} =
             Repo.get!(Deployment, deployment.id)

    assert %Server{status: :failed} = Repo.get!(Server, server.id)
  end

  test "fails deployments whose oban job has been purged" do
    {_server, deployment} = running_deployment()
    Repo.delete!(Repo.get!(Oban.Job, deployment.oban_job_id))

    Reconciler.reconcile()

    assert %Deployment{status: :failed, error_message: @orphan_message} =
             Repo.get!(Deployment, deployment.id)
  end

  test "leaves :running deployments alone when the oban job is still alive" do
    {server, deployment} = running_deployment()
    set_oban_state(deployment, "executing")

    Reconciler.reconcile()

    assert %Deployment{status: :running, error_message: nil} =
             Repo.get!(Deployment, deployment.id)

    assert %Server{status: :provisioning} = Repo.get!(Server, server.id)
  end

  test "skips deployments that are not :running" do
    {server, deployment} = running_deployment()
    {:ok, _} = Kura.mark_succeeded(deployment)
    set_oban_state(deployment, "discarded")

    Reconciler.reconcile()

    assert %Deployment{status: :succeeded} = Repo.get!(Deployment, deployment.id)
    assert %Server{status: :provisioning} = Repo.get!(Server, server.id)
  end

  test "does not unset :destroyed servers when reconciling an orphaned deployment" do
    {server, deployment} = running_deployment()
    {:ok, _} = Kura.mark_destroyed(server)
    set_oban_state(deployment, "discarded")

    Reconciler.reconcile()

    assert %Deployment{status: :failed} = Repo.get!(Deployment, deployment.id)
    assert %Server{status: :destroyed} = Repo.get!(Server, server.id)
  end
end
