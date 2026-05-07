defmodule Tuist.KuraTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  describe "latest_versions/1" do
    test "returns the runtime image tag from the current server deploy" do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

      assert [%{version: "sha-abcdef123456", released_at: nil}] = Kura.latest_versions(10)
    end

    test "caps the result at limit" do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

      assert Kura.latest_versions(0) == []
    end

    test "returns an empty list when no runtime image tag is configured" do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)

      assert Kura.latest_versions(10) == []
    end
  end

  describe "schedule_runtime_image_deployments/0" do
    test "enqueues deployments for active servers behind the runtime image tag" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.2")

      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "sha-abcdef123456" end)

      assert {:ok, [%Deployment{image_tag: "sha-abcdef123456"} = deployment]} =
               Kura.schedule_runtime_image_deployments()

      assert deployment.kura_server_id == server.id

      assert_enqueued(
        worker: RolloutWorker,
        args: %{"deployment_id" => deployment.id, "account_id" => account.id}
      )
    end

    test "does not enqueue deployments when the active server already runs the runtime image tag" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.3"
        })

      {:ok, _server} = Kura.activate_server(server, "0.5.3")

      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.3" end)

      assert {:ok, []} = Kura.schedule_runtime_image_deployments()
    end

    test "schedules a version only once per server" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.2")
      {:ok, _existing} = Kura.create_deployment(server, "0.5.3")

      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.3" end)

      assert {:ok, []} = Kura.schedule_runtime_image_deployments()
    end

    test "does not enqueue deployments when no runtime image tag is configured" do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)

      assert {:ok, []} = Kura.schedule_runtime_image_deployments()
    end
  end

  describe "create_deployment/2" do
    setup do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account.id,
          region: "local-controller",
          provisioner_node_ref: "kura-#{account.name}-local-controller"
        })
        |> Repo.insert()

      {:ok, account: account, server: server, user: user}
    end

    test "inserts a deployment row and enqueues the rollout worker", %{server: server} do
      assert {:ok, %Deployment{status: :pending} = deployment} =
               Kura.create_deployment(server, "sha-abcdef123456")

      assert deployment.oban_job_id
      assert deployment.kura_server_id == server.id
      assert deployment.cluster_id == "local-controller"

      assert_enqueued(
        worker: RolloutWorker,
        args: %{"deployment_id" => deployment.id}
      )
    end

    test "rejects an invalid OCI image tag", %{server: server} do
      assert {:error, %Ecto.Changeset{errors: [image_tag: _]}} =
               Kura.create_deployment(server, "bad tag")
    end
  end

  describe "list_deployments_for_account/1" do
    test "returns deployments newest first, scoped to the account" do
      user_a = AccountsFixtures.user_fixture()
      account_a = Accounts.get_account_from_user(user_a)
      user_b = AccountsFixtures.user_fixture()
      account_b = Accounts.get_account_from_user(user_b)

      {:ok, server_a} =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account_a.id,
          region: "local-controller",
          provisioner_node_ref: "kura-#{account_a.name}-local-controller"
        })
        |> Repo.insert()

      {:ok, server_b} =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account_b.id,
          region: "local-controller",
          provisioner_node_ref: "kura-#{account_b.name}-local-controller"
        })
        |> Repo.insert()

      {:ok, d1} = Kura.create_deployment(server_a, "0.5.0")
      {:ok, d2} = Kura.create_deployment(server_a, "0.5.1")
      {:ok, _other} = Kura.create_deployment(server_b, "0.5.0")

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

    test "inserts a server (provisioning) and an initial deployment + enqueues rollout", %{account: account} do
      assert {:ok, server} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "local-controller",
                 image_tag: "0.5.2"
               })

      assert server.status == :provisioning

      assert [%{image_tag: "0.5.2", kura_server_id: kura_server_id}] =
               server.deployments

      assert kura_server_id == server.id

      assert_enqueued(
        worker: RolloutWorker,
        args: %{"deployment_id" => List.first(server.deployments).id}
      )
    end

    test "rejects a region that is not available in the current environment", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [region: {"is not available in this environment", _}]}} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "eu-central",
                 image_tag: "0.5.2"
               })
    end

    test "rejects an unknown region", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [region: _]}} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "moon",
                 image_tag: "0.5.2"
               })
    end

    test "rejects a duplicate (account, region)", %{account: account} do
      attrs = %{
        account_id: account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      }

      assert {:ok, _} = Kura.create_server(attrs)
      assert {:error, %Ecto.Changeset{}} = Kura.create_server(attrs)
    end

    test "returns an account handle error when the generated Kubernetes name is too long" do
      user = AccountsFixtures.user_fixture(handle: String.duplicate("a", 32))
      account = Accounts.get_account_from_user(user)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "local-controller",
                 image_tag: "0.5.2"
               })

      assert {"is too long for Kura in this region; shorten it so the generated Kubernetes resource name stays under 53 characters",
              _} = changeset.errors[:account_handle]
    end

    test "ignores unknown string keys instead of raising", %{account: account} do
      assert {:ok, server} =
               Kura.create_server(%{
                 "account_id" => account.id,
                 "region" => "local-controller",
                 "image_tag" => "0.5.2",
                 "ignored-#{Ecto.UUID.generate()}" => "ignored"
               })

      assert server.region == "local-controller"
    end
  end

  describe "list_servers_for_account/1" do
    test "returns non-destroyed servers" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, kept} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, gone} =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account.id,
          region: "eu-central",
          provisioner_node_ref: "kura-tuist-eu-central-1"
        })
        |> Repo.insert()

      {:ok, gone} = Kura.destroy_server(gone)
      {:ok, _} = Kura.mark_destroyed(gone)

      ids = account.id |> Kura.list_servers_for_account() |> Enum.map(& &1.id)
      assert kept.id in ids
      refute gone.id in ids
    end
  end

  describe "list_nodes_for_server/2" do
    test "returns nodes through the server's provisioner scoped to the account" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      expect(Provisioner, :nodes, fn queried_server ->
        assert queried_server.id == server.id
        {:ok, [%{name: "kura-tuist-local-0", ready: true}]}
      end)

      assert {:ok, [%{name: "kura-tuist-local-0", ready: true}]} =
               Kura.list_nodes_for_server(account.id, server.id)
    end

    test "does not query Kubernetes for a server outside the account" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      other_account = Accounts.get_account_from_user(other_user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: other_account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      reject(&Provisioner.nodes/1)

      assert Kura.list_nodes_for_server(account.id, server.id) == {:error, :not_found}
    end
  end

  describe "activate_server/2" do
    test "reactivates a failed server when its cache endpoint already exists" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, active} = Kura.activate_server(server, "0.5.2")
      {:ok, failed} = Kura.fail_server(active)

      assert {:ok, active_again} = Kura.activate_server(failed, "0.5.3")
      assert active_again.status == :active
      assert active_again.current_image_tag == "0.5.3"

      assert [_] = Accounts.list_account_cache_endpoints(account, :kura)
    end
  end

  describe "destroy_server/1" do
    test "marks destroying, removes the cache endpoint, enqueues the destroy worker" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
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

    test "does not remove a default cache endpoint with the same URL" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.2")

      {:ok, default_endpoint} =
        %AccountCacheEndpoint{}
        |> AccountCacheEndpoint.create_changeset(%{
          account_id: account.id,
          technology: :default,
          url: server.url
        })
        |> Repo.insert()

      assert {:ok, _server} = Kura.destroy_server(server)

      assert Accounts.list_account_cache_endpoints(account, :kura) == []
      assert [endpoint] = Accounts.list_account_cache_endpoints(account, :default)
      assert endpoint.id == default_endpoint.id
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
          region: "local-controller",
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
