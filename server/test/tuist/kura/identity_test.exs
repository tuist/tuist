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

  test "renaming preserves the complete workload manifest, endpoints and tenant owner" do
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
    assert KubernetesController.manifest(ref, "0.52.1", renamed, region, renamed_server) == before
    assert Provisioner.public_url(renamed, renamed_server) == url
    assert Provisioner.grpc_public_url(renamed, renamed_server) == Provisioner.grpc_public_url(account, server)

    assert KubernetesController.manifest_revision(server, region) ==
             KubernetesController.manifest_revision(renamed_server, region)

    expect(Capacity, :egress_headroom, fn region_id, handle ->
      assert region_id == region.id
      assert handle == tenant
      nil
    end)

    assert EgressLimits.node_headroom(renamed, region) == nil

    assert Identity.account_ids([tenant, String.upcase(renamed.name)]) ==
             %{tenant => account.id, String.upcase(renamed.name) => account.id}
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
