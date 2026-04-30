defmodule Tuist.KuraTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraVersion
  alias Tuist.Kura.Workers.RolloutWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "record_version/2" do
    test "inserts a new version" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, %KuraVersion{version: "0.5.2"}} = Kura.record_version("0.5.2", now)
    end

    test "is idempotent on duplicate version" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} = Kura.record_version("0.5.2", now)
      assert {:ok, _} = Kura.record_version("0.5.2", now)

      assert length(Kura.latest_versions(10)) == 1
    end
  end

  describe "latest_versions/1" do
    test "returns versions sorted newest first" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _} = Kura.record_version("0.5.0", DateTime.add(now, -3600, :second))
      {:ok, _} = Kura.record_version("0.5.1", DateTime.add(now, -1800, :second))
      {:ok, _} = Kura.record_version("0.5.2", now)

      assert ["0.5.2", "0.5.1", "0.5.0"] ==
               Kura.latest_versions(10) |> Enum.map(& &1.version)
    end
  end

  describe "create_deployment/1" do
    setup do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, account: account, user: user}
    end

    test "inserts a deployment row and enqueues the rollout worker", %{account: account} do
      assert {:ok, %KuraDeployment{status: :pending} = deployment} =
               Kura.create_deployment(%{
                 account_id: account.id,
                 cluster_id: "eu-1",
                 image_tag: "0.5.2"
               })

      assert deployment.oban_job_id

      assert_enqueued(
        worker: RolloutWorker,
        args: %{"deployment_id" => deployment.id}
      )
    end

    test "rejects an unknown cluster", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [cluster_id: _]}} =
               Kura.create_deployment(%{
                 account_id: account.id,
                 cluster_id: "moon-1",
                 image_tag: "0.5.2"
               })
    end

    test "rejects a non-semver image tag", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [image_tag: _]}} =
               Kura.create_deployment(%{
                 account_id: account.id,
                 cluster_id: "eu-1",
                 image_tag: "latest"
               })
    end
  end

  describe "list_deployments_for_account/1" do
    test "returns deployments newest first, scoped to the account" do
      user_a = AccountsFixtures.user_fixture()
      account_a = Accounts.get_account_from_user(user_a)
      user_b = AccountsFixtures.user_fixture()
      account_b = Accounts.get_account_from_user(user_b)

      {:ok, d1} =
        Kura.create_deployment(%{
          account_id: account_a.id,
          cluster_id: "eu-1",
          image_tag: "0.5.0"
        })

      {:ok, _other} =
        Kura.create_deployment(%{
          account_id: account_b.id,
          cluster_id: "eu-1",
          image_tag: "0.5.0"
        })

      {:ok, d2} =
        Kura.create_deployment(%{
          account_id: account_a.id,
          cluster_id: "eu-1",
          image_tag: "0.5.1"
        })

      result = Kura.list_deployments_for_account(account_a.id, 10)
      assert Enum.map(result, & &1.id) == [d2.id, d1.id]
    end
  end

  describe "create_server/1" do
    setup do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, account: account, user: user}
    end

    test "inserts a server (provisioning) and an initial deployment + enqueues rollout", %{account: account, user: user} do
      assert {:ok, server} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "eu",
                 spec: :medium,
                 volume_size_gi: 200,
                 image_tag: "0.5.2"
               })

      assert server.status == :provisioning
      assert server.spec == :medium
      assert server.volume_size_gi == 200

      assert [%{image_tag: "0.5.2", kura_server_id: kura_server_id}] =
               server.deployments

      assert kura_server_id == server.id

      assert_enqueued(
        worker: Tuist.Kura.Workers.RolloutWorker,
        args: %{"deployment_id" => List.first(server.deployments).id}
      )
    end

    test "fills volume_size_gi from spec defaults when omitted", %{account: account} do
      assert {:ok, server} =
               Kura.create_server(%{
                 account_id: account.id,
                 cluster_id: "eu-1",
                 spec: :small,
                 image_tag: "0.5.2"
               })

      assert server.volume_size_gi == 50
    end

    test "rejects an unknown cluster", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [cluster_id: _]}} =
               Kura.create_server(%{
                 account_id: account.id,
                 cluster_id: "moon-1",
                 spec: :medium,
                 image_tag: "0.5.2"
               })
    end

    test "rejects a duplicate (account, cluster, spec)", %{account: account} do
      attrs = %{
        account_id: account.id,
        cluster_id: "eu-1",
        spec: :medium,
        image_tag: "0.5.2"
      }

      assert {:ok, _} = Kura.create_server(attrs)
      assert {:error, %Ecto.Changeset{}} = Kura.create_server(attrs)
    end
  end

  describe "list_servers_for_account/1" do
    test "returns active servers, omits destroyed" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, kept} =
        Kura.create_server(%{
          account_id: account.id,
          cluster_id: "eu-1",
          spec: :small,
          image_tag: "0.5.2"
        })

      {:ok, gone} =
        Kura.create_server(%{
          account_id: account.id,
          cluster_id: "eu-1",
          spec: :large,
          image_tag: "0.5.2"
        })

      {:ok, _} = Kura.mark_destroyed(gone)

      ids = Kura.list_servers_for_account(account.id) |> Enum.map(& &1.id)
      assert kept.id in ids
      refute gone.id in ids
    end
  end

  describe "destroy_server/1" do
    test "marks destroying, removes the cache endpoint, enqueues the destroy worker" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          cluster_id: "eu-1",
          spec: :medium,
          image_tag: "0.5.2"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.2")
      assert server.status == :active

      assert [%{url: _url}] = Accounts.list_account_cache_endpoints(account, :kura)

      assert {:ok, server} = Kura.destroy_server(server)
      assert server.status == :destroying
      assert Accounts.list_account_cache_endpoints(account, :kura) == []

      assert_enqueued(worker: Tuist.Kura.Workers.DestroyServerWorker, args: %{"server_id" => server.id})
    end
  end

  describe "subscribe_to_account/1" do
    test "broadcasts created/updated/destroyed events to the account topic" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      :ok = Kura.subscribe_to_account(account.id)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          cluster_id: "eu-1",
          spec: :medium,
          image_tag: "0.5.2"
        })

      assert_receive {:kura_server, :created, %{id: id1}}
      assert id1 == server.id

      {:ok, _} = Kura.activate_server(server, "0.5.2")
      assert_receive {:kura_server, :updated, _}

      {:ok, _} = Kura.destroy_server(server)
      assert_receive {:kura_server, :updated, %{status: :destroying}}
    end
  end
end
