defmodule Tuist.Kura.IdentityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Organization
  alias Tuist.Environment
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.EgressLimits
  alias Tuist.Kura.Identity
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures

  test "renaming migrates client endpoints while preserving workload, peer and storage identity" do
    account = AccountsFixtures.organization_fixture().account
    tenant = account.name
    region = Regions.get("eu-west")
    {:ok, ref} = KubernetesController.provision(account, region, %Server{})
    server = %Server{account: account, region: region.id, provisioner_node_ref: ref}
    before = KubernetesController.manifest(ref, "0.52.1", account, region, server)
    url = Provisioner.public_url(account, server)

    {:ok, renamed} = Accounts.update_account(account, %{name: "renamed-#{System.unique_integer([:positive])}"})
    renamed_server = %{server | account: renamed}

    assert renamed.kura_tenant_id == tenant
    assert Identity.account(tenant).id == account.id
    assert Accounts.get_account_by_handle(tenant) == nil
    assert KubernetesController.provision(renamed, region, %Server{}) == {:ok, ref}
    after_rename = KubernetesController.manifest(ref, "0.52.1", renamed, region, renamed_server)
    endpoint_fields = ["publicHost", "grpcPublicHost", "privateHost", "clientHostAliases"]
    assert Map.drop(after_rename["spec"], endpoint_fields) == Map.drop(before["spec"], endpoint_fields)
    assert after_rename["metadata"]["name"] == before["metadata"]["name"]
    assert after_rename["spec"]["clientHostAliases"] == [URI.parse(url).host]
    assert Provisioner.public_url(renamed, renamed_server) != url
    assert Provisioner.grpc_public_url(renamed, renamed_server) != Provisioner.grpc_public_url(account, server)
    assert Provisioner.internal_url(renamed, renamed_server) == Provisioner.internal_url(account, server)

    refute KubernetesController.manifest_revision(server, region) ==
             KubernetesController.manifest_revision(renamed_server, region)

    assert Identity.account_for_handle(tenant).id == account.id

    expect(Capacity, :egress_headroom, fn region_id, handle ->
      assert region_id == region.id
      assert handle == tenant
      nil
    end)

    assert EgressLimits.node_headroom(renamed, region) == nil

    assert Identity.account_ids([tenant, String.upcase(renamed.name)]) ==
             %{tenant => account.id, String.upcase(renamed.name) => account.id}
  end

  test "redirects wait for activated URLs and every alias points directly to the latest name" do
    account = AccountsFixtures.organization_fixture().account
    server = KuraFixtures.active_server_fixture(account, region: "eu-west")
    original_url = Provisioner.public_url(account, server)
    server = server |> Ecto.Changeset.change(url: original_url) |> Repo.update!()
    {:ok, renamed} = Accounts.update_account(account, %{name: "middle-#{account.id}"})
    assert Identity.endpoint_redirects(renamed) == %{}
    middle_url = Provisioner.public_url(renamed, server)
    server = server |> Ecto.Changeset.change(url: middle_url) |> Repo.update!()
    assert Identity.endpoint_redirects(renamed) == %{URI.parse(original_url).host => middle_url}
    {:ok, latest} = Accounts.update_account(renamed, %{name: "latest-#{account.id}"})
    assert Identity.endpoint_redirects(latest) == %{}
    latest_url = Provisioner.public_url(latest, server)
    server |> Ecto.Changeset.change(url: latest_url) |> Repo.update!()

    assert Identity.endpoint_redirects(latest) == %{
             URI.parse(original_url).host => latest_url,
             URI.parse(middle_url).host => latest_url
           }

    {:ok, restored} = Accounts.update_account(latest, %{name: account.name})
    server |> Ecto.Changeset.change(url: original_url) |> Repo.update!()

    assert Identity.endpoint_redirects(restored) == %{
             URI.parse(latest_url).host => original_url,
             URI.parse(middle_url).host => original_url
           }

    assert Identity.handles(restored) == Enum.sort([account.name, renamed.name, latest.name])
  end

  test "retired handles cannot be reused by another account, including changeset creation" do
    account = AccountsFixtures.organization_fixture().account
    other = AccountsFixtures.organization_fixture().account
    {:ok, renamed} = Accounts.update_account(account, %{name: "renamed-#{System.unique_integer([:positive])}"})

    assert {:error, changeset} = Accounts.update_account(other, %{name: String.upcase(account.name)})
    assert "is reserved by another account" in errors_on(changeset).name

    organization = Repo.insert!(%Organization{})

    assert {:error, changeset} =
             %Account{}
             |> Account.create_changeset(%{
               name: account.name,
               organization_id: organization.id,
               billing_email: "test@example.com"
             })
             |> Repo.insert()

    assert "is reserved by another account" in errors_on(changeset).name
    assert {:ok, restored} = Accounts.update_account(renamed, %{name: account.name})
    assert restored.kura_tenant_id == account.kura_tenant_id
  end

  test "the database rejects identity changes even outside account changesets" do
    account = AccountsFixtures.organization_fixture().account

    assert_raise Postgrex.Error, ~r/Kura tenant identity is immutable/, fn ->
      Repo.query!("UPDATE accounts SET kura_tenant_id = $1 WHERE id = $2", ["changed-identity", account.id])
    end
  end

  test "production renames with a Kura server require the explicit runtime rollout gate" do
    account = AccountsFixtures.organization_fixture().account
    KuraFixtures.active_server_fixture(account, region: "eu-west")
    stub(Environment, :env, fn -> :prod end)

    assert {:error, changeset} = Accounts.update_account(account, %{name: "gated-#{account.id}"})
    assert "cannot be changed until the cache supports account renames" in errors_on(changeset).name

    FunWithFlags.enable(:kura_account_rename, for_actor: account)
    assert {:ok, renamed} = Accounts.update_account(account, %{name: "gated-#{account.id}"})
    assert renamed.kura_tenant_id == account.kura_tenant_id
  end
end
