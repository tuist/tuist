defmodule Tuist.KuraTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.DataCase

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_global

  setup do
    Cachex.del(:tuist, "Elixir.Tuist.Kura-versions")
    :ok
  end

  describe "latest_versions/1" do
    test "returns kura@* releases newest first" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"tag_name" => "kura@0.5.0", "published_at" => "2026-04-01T00:00:00Z"},
             %{"tag_name" => "kura@0.5.2", "published_at" => "2026-04-29T00:00:00Z"},
             %{"tag_name" => "kura@0.5.1", "published_at" => "2026-04-15T00:00:00Z"},
             %{"tag_name" => "tuist@4.188.3", "published_at" => "2026-04-15T00:00:00Z"}
           ]
         }}
      end)

      assert ["0.5.2", "0.5.1", "0.5.0"] ==
               10 |> Kura.latest_versions() |> Enum.map(& &1.version)
    end

    test "returns an empty list when GitHub is unreachable" do
      stub(Req, :get, fn _url, _opts -> {:error, :timeout} end)

      assert Kura.latest_versions(10) == []
    end

    test "does not cache a failed GitHub fetch" do
      stub(Req, :get, fn _url, _opts ->
        call_count = Process.get(:github_release_call_count, 0)
        Process.put(:github_release_call_count, call_count + 1)

        case call_count do
          0 ->
            {:error, :timeout}

          _ ->
            {:ok,
             %Req.Response{
               status: 200,
               body: [
                 %{"tag_name" => "kura@0.5.2", "published_at" => "2026-04-29T00:00:00Z"}
               ]
             }}
        end
      end)

      assert Kura.latest_versions(10) == []
      assert ["0.5.2"] == 10 |> Kura.latest_versions() |> Enum.map(& &1.version)
    end

    test "caps the result at limit" do
      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body:
             for n <- 0..30 do
               %{"tag_name" => "kura@0.5.#{n}", "published_at" => "2026-04-#{rem(n, 28) + 1}T00:00:00Z"}
             end
         }}
      end)

      assert length(Kura.latest_versions(5)) == 5
    end
  end

  describe "create_deployment/1" do
    setup do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, account: account, user: user}
    end

    test "inserts a deployment row and enqueues the rollout worker", %{account: account} do
      assert {:ok, %Deployment{status: :pending} = deployment} =
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
                 region: "local",
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
        worker: RolloutWorker,
        args: %{"deployment_id" => List.first(server.deployments).id}
      )
    end

    test "fills volume_size_gi from spec defaults when omitted", %{account: account} do
      assert {:ok, server} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "local",
                 spec: :small,
                 image_tag: "0.5.2"
               })

      assert server.volume_size_gi == 50
    end

    test "rejects a region that is not available in the current environment", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [region: {"is not available in this environment", _}]}} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "eu",
                 spec: :medium,
                 image_tag: "0.5.2"
               })
    end

    test "rejects an unknown region", %{account: account} do
      assert {:error, %Ecto.Changeset{errors: [region: _]}} =
               Kura.create_server(%{
                 account_id: account.id,
                 region: "moon",
                 spec: :medium,
                 image_tag: "0.5.2"
               })
    end

    test "rejects a duplicate (account, region)", %{account: account} do
      attrs = %{
        account_id: account.id,
        region: "local",
        spec: :medium,
        image_tag: "0.5.2"
      }

      assert {:ok, _} = Kura.create_server(attrs)
      assert {:error, %Ecto.Changeset{}} = Kura.create_server(attrs)
    end
  end

  describe "list_servers_for_account/1" do
    test "returns non-destroyed servers" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, kept} =
        Kura.create_server(%{
          account_id: account.id,
          region: "local",
          spec: :small,
          image_tag: "0.5.2"
        })

      {:ok, gone} =
        %Server{}
        |> Server.create_changeset(%{
          account_id: account.id,
          region: "eu",
          spec: :small,
          volume_size_gi: 50,
          provisioner_node_ref: "kura-tuist-eu-1"
        })
        |> Repo.insert()

      {:ok, _} = Kura.mark_destroyed(gone)

      ids = account.id |> Kura.list_servers_for_account() |> Enum.map(& &1.id)
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
          region: "local",
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
          region: "local",
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
