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

  test "appends the synthetic failure line after streamed output without reusing sequence ids" do
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
