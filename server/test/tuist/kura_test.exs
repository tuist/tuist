defmodule Tuist.KuraTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
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

    test "returns the deploy-configured runtime image tag outside dev and test" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.2" end)

      assert [%{version: "0.5.2", image_tag: "0.5.2", released_at: nil}] = Kura.latest_versions(10)
    end
  end

  describe "version_label/1" do
    test "strips the Kura release tag prefix" do
      assert Kura.version_label("kura@0.5.2") == "0.5.2"
    end

    test "leaves runtime image tags unchanged" do
      assert Kura.version_label("0.5.2") == "0.5.2"
      assert Kura.version_label("sha-abcdef123456") == "sha-abcdef123456"
    end
  end

  describe "schedule_runtime_image_deployments/0" do
    test "creates deployments for active servers behind the runtime image tag" do
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
    end

    test "does not create deployments when the active server already runs the runtime image tag" do
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

    test "does not create deployments when no runtime image tag is configured" do
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> nil end)

      assert {:ok, []} = Kura.schedule_runtime_image_deployments()
    end

    test "schedules the deploy-configured runtime image tag outside dev and test" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.1"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.1")

      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.5.2" end)

      assert {:ok, [%Deployment{image_tag: "0.5.2"} = deployment]} =
               Kura.schedule_runtime_image_deployments()

      assert deployment.kura_server_id == server.id
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

    test "inserts a deployment row for the reconciler", %{server: server} do
      assert {:ok, %Deployment{status: :pending} = deployment} =
               Kura.create_deployment(server, "sha-abcdef123456")

      assert deployment.kura_server_id == server.id
      assert deployment.cluster_id == "local-controller"
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

    test "inserts a server (provisioning) and an initial deployment", %{account: account} do
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

  describe "activate_server/2" do
    test "does not activate a server until the public HTTPS endpoint is ready" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      expect(Provisioner, :public_url, fn account_arg, %Server{id: id} ->
        assert account_arg.id == account.id
        assert id == server.id
        "https://localhost:4100"
      end)

      expect(Req, :get, fn "https://localhost:4100/up", opts ->
        refute Keyword.has_key?(opts, :finch)
        assert opts[:receive_timeout] == 5_000
        assert opts[:connect_options] == [timeout: 5_000]
        assert opts[:retry] == false
        {:error, %Mint.TransportError{reason: {:tls_alert, ~c"unknown ca"}}}
      end)

      assert {:error, {:public_endpoint_not_ready, "localhost", %Mint.TransportError{}}} =
               Kura.activate_server(server, "0.5.2")

      assert %Server{status: :provisioning, current_image_tag: nil, url: nil} = Repo.get!(Server, server.id)
      assert Accounts.list_account_cache_endpoints(account, :kura) == []
    end

    test "returns endpoint not ready instead of raising when the HTTPS readiness probe cannot connect" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      expect(Provisioner, :public_url, fn account_arg, %Server{id: id} ->
        assert account_arg.id == account.id
        assert id == server.id
        "https://localhost:65534"
      end)

      assert {:error, {:public_endpoint_not_ready, "localhost", reason}} =
               Kura.activate_server(server, "0.5.2")

      refute match?(%ArgumentError{}, reason)
    end

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
    test "marks destroying and removes the cache endpoint" do
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

  describe "retry_server/2" do
    test "tombstones the failed row and creates a fresh server in the same region" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, failed} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, failed} = Kura.fail_server(failed)

      assert {:ok, %Server{status: :provisioning, region: "local-controller"} = new_server} =
               Kura.retry_server(failed, "0.5.3")

      refute new_server.id == failed.id
      assert %Server{status: :destroyed} = Repo.get!(Server, failed.id)

      new_server = Repo.preload(new_server, :deployments)
      assert [%Deployment{status: :pending, image_tag: "0.5.3"}] = new_server.deployments
    end

    test "broadcasts :destroyed for the old row and :created for the new one" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      :ok = Kura.subscribe_to_account(account.id)

      {:ok, failed} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      assert_receive {:kura_server, :created, _}

      {:ok, failed} = Kura.fail_server(failed)
      {:ok, _new_server} = Kura.retry_server(failed, "0.5.3")

      assert_receive {:kura_server, :destroyed, %{status: :destroyed}}
      assert_receive {:kura_server, :created, %{status: :provisioning}}
    end

    test "refuses to retry a previously-active server" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      {:ok, server} = Kura.activate_server(server, "0.5.2")
      {:ok, server} = Kura.fail_server(server)

      assert {:error, :not_retryable} = Kura.retry_server(server, "0.5.3")
      assert %Server{status: :failed, current_image_tag: "0.5.2"} = Repo.get!(Server, server.id)
    end

    test "refuses to retry a server that's not in :failed state" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local-controller",
          image_tag: "0.5.2"
        })

      assert {:error, :not_retryable} = Kura.retry_server(server, "0.5.3")
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
