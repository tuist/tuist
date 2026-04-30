defmodule Tuist.Kura.Workers.DestroyServerWorkerTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  import ExUnit.CaptureLog
  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.Provisioner
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
        region: "eu",
        spec: :small,
        image_tag: "0.5.2"
      })

    {:ok, account: account, server: server}
  end

  describe "perform/1" do
    test "marks the row destroyed and stops on a missing server" do
      log = capture_log(fn ->
        :ok = perform_for("00000000-0000-0000-0000-000000000000")
      end)

      assert log =~ "server 00000000-0000-0000-0000-000000000000 not found"
    end

    test "is a no-op for an already-destroyed row", %{server: server} do
      reject(&Provisioner.destroy/1)
      {:ok, _} = Kura.mark_destroyed(server)

      assert :ok = perform_for(server.id)
    end

    test "calls the provisioner and marks destroyed on success", %{server: server} do
      ref = make_ref()
      test_pid = self()

      stub(Provisioner, :destroy, fn %KuraServer{id: id} ->
        send(test_pid, {ref, :destroy_called, id})
        :ok
      end)

      assert :ok = perform_for(server.id)
      assert_received {^ref, :destroy_called, server_id} when server_id == server.id

      assert %KuraServer{status: :destroyed} = Repo.get!(KuraServer, server.id)
    end

    test "logs and still marks destroyed when the region is no longer in the catalog", %{server: server} do
      stub(Provisioner, :destroy, fn _ -> {:error, :not_found} end)

      log =
        capture_log(fn ->
          assert :ok = perform_for(server.id)
        end)

      assert log =~ "region #{server.region} not in catalog"
      assert %KuraServer{status: :destroyed} = Repo.get!(KuraServer, server.id)
    end

    test "logs and still marks destroyed when the provisioner fails", %{server: server} do
      stub(Provisioner, :destroy, fn _ -> {:error, "helm uninstall exited 1"} end)

      log =
        capture_log(fn ->
          assert :ok = perform_for(server.id)
        end)

      assert log =~ "provisioner destroy failed"
      assert log =~ "helm uninstall exited 1"
      assert %KuraServer{status: :destroyed} = Repo.get!(KuraServer, server.id)
    end
  end

  defp perform_for(server_id) do
    DestroyServerWorker.perform(%Oban.Job{args: %{"server_id" => server_id}})
  end
end
