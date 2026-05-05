defmodule Tuist.Kura.Workers.DestroyServerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.DestroyServerWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

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
    test "returns :ok for a missing server", %{account: account} do
      assert :ok = perform_for(account.id, Ecto.UUID.generate())
    end

    test "returns :ok when the server belongs to a different account", %{server: server} do
      reject(&Provisioner.destroy/1)
      other_user = AccountsFixtures.user_fixture()
      other_account = Accounts.get_account_from_user(other_user)
      {:ok, _} = Kura.destroy_server(server)

      assert :ok = perform_for(other_account.id, server.id)
      assert %Server{status: :destroying} = Repo.get!(Server, server.id)
    end

    test "is a no-op for an already-destroyed row", %{account: account, server: server} do
      reject(&Provisioner.destroy/1)
      {:ok, server} = Kura.destroy_server(server)
      {:ok, _} = Kura.mark_destroyed(server)

      assert :ok = perform_for(account.id, server.id)
    end

    test "is a no-op for a row that has not entered destroying", %{account: account, server: server} do
      reject(&Provisioner.destroy/1)

      assert :ok = perform_for(account.id, server.id)
      assert %Server{status: :provisioning} = Repo.get!(Server, server.id)
    end

    test "calls the provisioner and marks destroyed on success", %{account: account, server: server} do
      ref = make_ref()
      test_pid = self()
      {:ok, server} = Kura.destroy_server(server)

      stub(Provisioner, :destroy, fn %Server{id: id} ->
        send(test_pid, {ref, :destroy_called, id})
        :ok
      end)

      assert :ok = perform_for(account.id, server.id)
      assert_received {^ref, :destroy_called, server_id} when server_id == server.id

      assert %Server{status: :destroyed} = Repo.get!(Server, server.id)
    end

    test "returns an error and keeps the row destroying when the region is no longer in the catalog", %{
      account: account,
      server: server
    } do
      {:ok, server} = Kura.destroy_server(server)
      stub(Provisioner, :destroy, fn _ -> {:error, :not_found} end)

      assert {:error, {:provisioner_destroy_failed, :not_found}} = perform_for(account.id, server.id)
      assert %Server{status: :destroying} = Repo.get!(Server, server.id)
    end

    test "returns an error and keeps the row destroying when the provisioner fails", %{
      account: account,
      server: server
    } do
      {:ok, server} = Kura.destroy_server(server)
      stub(Provisioner, :destroy, fn _ -> {:error, "helm uninstall exited 1"} end)

      assert {:error, {:provisioner_destroy_failed, "helm uninstall exited 1"}} =
               perform_for(account.id, server.id)

      assert %Server{status: :destroying} = Repo.get!(Server, server.id)
    end

    test "enqueued destroy jobs allow retries", %{account: account, server: server} do
      assert {:ok, _server} = Kura.destroy_server(server)

      assert_enqueued(
        worker: DestroyServerWorker,
        args: %{"server_id" => server.id, "account_id" => account.id},
        queue: :kura_rollout,
        max_attempts: 5
      )
    end
  end

  defp perform_for(account_id, server_id) do
    DestroyServerWorker.perform(%Oban.Job{args: %{"server_id" => server_id, "account_id" => account_id}})
  end
end
