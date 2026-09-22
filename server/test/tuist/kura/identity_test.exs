defmodule Tuist.Kura.IdentityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

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
  alias Tuist.Time
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

  test "client URLs expire at 90 days without changing identity, analytics or name ownership" do
    original = AccountsFixtures.organization_fixture(name: "original-#{System.unique_integer([:positive])}").account
    server = KuraFixtures.active_server_fixture(original, region: "eu-west")
    {:ok, account} = Accounts.update_account(original, %{name: "renamed-#{original.id}"})
    canonical = Provisioner.public_url(account, server)
    server = server |> Ecto.Changeset.change(url: canonical) |> Repo.update!() |> Map.put(:account, account)
    region = Regions.get(server.region)
    ref = server.provisioner_node_ref
    deadline = client_url_deadline(original.name)

    assert Repo.query!(
             "SELECT client_url_expires_at = now() + interval '90 days' FROM account_handle_reservations WHERE name = $1",
             [original.name]
           ).rows == [[true]]

    assert client_url_deadline(account.name) == nil

    stub(Time, :utc_now, fn -> DateTime.add(deadline, -1, :second) end)
    before = KubernetesController.manifest(ref, "0.52.1", account, region, server)
    before_revision = KubernetesController.manifest_revision(server, region)
    assert Identity.client_handles(account) == Enum.sort([original.name, account.name])

    assert Identity.endpoint_redirects(account) == %{
             URI.parse(Provisioner.public_url(original, server)).host => canonical
           }

    stub(Time, :utc_now, fn -> deadline end)
    after_expiry = KubernetesController.manifest(ref, "0.52.1", account, region, server)
    assert Identity.client_handles(account) == [account.name]
    assert Identity.endpoint_redirects(account) == %{}
    refute Map.has_key?(after_expiry["spec"], "clientHostAliases")
    assert Map.delete(after_expiry["spec"], "clientHostAliases") == Map.delete(before["spec"], "clientHostAliases")
    refute KubernetesController.manifest_revision(server, region) == before_revision
    assert Identity.tenant_id(account) == original.name
    assert original.name in Identity.handles(account)
    assert Identity.account_ids([original.name]) == %{original.name => account.id}
    assert Identity.account_for_handle(original.name).id == account.id
  end

  test "each alias has its own deadline and rename-back resets only that name" do
    original = AccountsFixtures.organization_fixture().account
    {:ok, middle} = Accounts.update_account(original, %{name: "middle-#{original.id}"})
    earlier_deadline = DateTime.add(DateTime.utc_now(), 10, :day)

    Repo.update_all(from(r in "account_handle_reservations", where: r.name == ^original.name),
      set: [client_url_expires_at: earlier_deadline]
    )

    {:ok, latest} = Accounts.update_account(middle, %{name: "latest-#{original.id}"})
    assert client_url_deadline(original.name) == earlier_deadline
    middle_deadline = client_url_deadline(middle.name)
    assert DateTime.after?(middle_deadline, earlier_deadline)

    stub(Time, :utc_now, fn -> earlier_deadline end)
    assert Identity.client_handles(latest) == Enum.sort([middle.name, latest.name])
    {:ok, restored} = Accounts.update_account(latest, %{name: original.name})
    assert client_url_deadline(original.name) == nil
    assert client_url_deadline(middle.name) == middle_deadline
    assert original.name in Identity.client_handles(restored)
    {:ok, _} = Accounts.update_account(restored, %{name: "final-#{original.id}"})
    assert DateTime.after?(client_url_deadline(original.name), earlier_deadline)
  end

  test "new and existing accounts cannot claim an alias before or after URL expiry" do
    original = AccountsFixtures.organization_fixture().account
    other = AccountsFixtures.organization_fixture().account
    {:ok, middle} = Accounts.update_account(original, %{name: "middle-#{original.id}"})
    {:ok, latest} = Accounts.update_account(middle, %{name: "latest-#{original.id}"})
    deadline = client_url_deadline(middle.name)

    for now <- [DateTime.add(deadline, -1, :second), deadline] do
      stub(Time, :utc_now, fn -> now end)
      assert middle.name in Identity.client_handles(latest) == DateTime.before?(now, deadline)
      assert {:error, changeset} = Accounts.update_account(other, %{name: String.upcase(middle.name)})
      assert "is reserved by another account" in errors_on(changeset).name
      organization = Repo.insert!(%Organization{})

      assert {:error, changeset} =
               %Account{}
               |> Account.create_changeset(%{
                 name: String.upcase(middle.name),
                 organization_id: organization.id,
                 billing_email: "test@example.com"
               })
               |> Repo.insert()

      assert "is reserved by another account" in errors_on(changeset).name
    end
  end

  defp client_url_deadline(handle) do
    Repo.one!(
      from(r in "account_handle_reservations",
        where: r.name == ^handle,
        select: type(r.client_url_expires_at, :utc_datetime_usec)
      )
    )
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
