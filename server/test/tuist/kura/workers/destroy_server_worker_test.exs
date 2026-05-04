defmodule Tuist.Kura.Workers.DestroyServerWorkerTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.DestroyServerWorker
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

    {:ok, account: account, server: server}
  end

  describe "perform/1" do
    test "returns :ok for a missing server" do
      assert :ok = perform_for(Ecto.UUID.generate())
    end

    test "is a no-op for an already-destroyed row", %{server: server} do
      reject(&Provisioner.destroy/1)
      {:ok, _} = Kura.mark_destroyed(server)

      assert :ok = perform_for(server.id)
    end

    test "is a no-op for a row that has not entered destroying", %{server: server} do
      reject(&Provisioner.destroy/1)

      assert :ok = perform_for(server.id)
      assert %Server{status: :provisioning} = Repo.get!(Server, server.id)
    end

    test "calls the provisioner and marks destroyed on success", %{server: server} do
      ref = make_ref()
      test_pid = self()
      {:ok, server} = Kura.destroy_server(server)

      stub(Provisioner, :destroy, fn %Server{id: id} ->
        send(test_pid, {ref, :destroy_called, id})
        :ok
      end)

      assert :ok = perform_for(server.id)
      assert_received {^ref, :destroy_called, server_id} when server_id == server.id

      assert %Server{status: :destroyed} = Repo.get!(Server, server.id)
    end

    test "returns an error and keeps the row destroying when the region is no longer in the catalog", %{
      server: server
    } do
      {:ok, server} = Kura.destroy_server(server)
      stub(Provisioner, :destroy, fn _ -> {:error, :not_found} end)

      assert {:error, {:provisioner_destroy_failed, :not_found}} = perform_for(server.id)
      assert %Server{status: :destroying} = Repo.get!(Server, server.id)
    end

    test "returns an error and keeps the row destroying when the provisioner fails", %{server: server} do
      {:ok, server} = Kura.destroy_server(server)
      stub(Provisioner, :destroy, fn _ -> {:error, "helm uninstall exited 1"} end)

      assert {:error, {:provisioner_destroy_failed, "helm uninstall exited 1"}} = perform_for(server.id)
      assert %Server{status: :destroying} = Repo.get!(Server, server.id)
    end

    test "enqueued destroy jobs allow retries", %{server: server} do
      assert {:ok, _server} = Kura.destroy_server(server)

      assert_enqueued(
        worker: DestroyServerWorker,
        args: %{"server_id" => server.id},
        queue: :kura_rollout,
        max_attempts: 5
      )
    end
  end

  defp perform_for(server_id) do
    DestroyServerWorker.perform(%Oban.Job{args: %{"server_id" => server_id}})
  end
end
