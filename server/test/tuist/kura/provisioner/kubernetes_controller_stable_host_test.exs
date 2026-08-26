defmodule Tuist.Kura.Provisioner.KubernetesControllerStableHostTest do
  # The ownership decision reads the account's instance set from the database,
  # so unlike the rest of the manifest these cases need a real row rather than
  # a struct.
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> ["eu-central", "us-east"] end)

    :ok
  end

  test "renders the region-independent host onto the instance that answers on it" do
    account = account()
    server = instance(account, "eu-central")
    {:ok, _row} = PlacerRegions.put_primary(account, "eu-central")

    spec = manifest(account, server, "eu-central")["spec"]

    assert spec["stableHost"] == Regions.stable_public_host(account.name)
    assert spec["publicHost"] =~ "eu-central"
    refute spec["stableHost"] =~ "eu-central"
  end

  test "leaves it off every instance that does not answer on it" do
    account = account()
    primary = instance(account, "eu-central")
    secondary = instance(account, "us-east")
    {:ok, _row} = PlacerRegions.put_primary(account, "eu-central")
    {:ok, _row} = PlacerRegions.put_secondary(account, "us-east")

    assert manifest(account, primary, "eu-central")["spec"]["stableHost"]
    refute manifest(account, secondary, "us-east")["spec"]["stableHost"]
  end

  test "moves it to the destination once that instance is serving" do
    account = account()
    source = instance(account, "eu-central")
    destination = instance(account, "us-east", :provisioning)
    {:ok, _held} = PlacerRegions.put_primary(account, "eu-central")
    {:ok, _moved} = PlacerRegions.put_primary(account, "us-east")

    # Still coming up, so the source keeps answering on the name.
    assert manifest(account, source, "eu-central")["spec"]["stableHost"]
    refute manifest(account, destination, "us-east")["spec"]["stableHost"]

    {:ok, _serving} = destination |> Server.observation_changeset(%{status: :active}) |> Repo.update()

    refute manifest(account, source, "eu-central")["spec"]["stableHost"]
    assert manifest(account, destination, "us-east")["spec"]["stableHost"]
  end

  test "the manifest revision moves with the host, so the reconciler re-applies both rows" do
    # The reconciler only re-renders on a revision mismatch. Without the host in
    # the revision nothing re-applies when it changes hands, and the name stays
    # on the instance that is about to be destroyed — dead exactly when a
    # relocation was supposed to be carrying it across.
    account = account()
    source = instance(account, "eu-central")
    destination = instance(account, "us-east", :provisioning)
    {:ok, _held} = PlacerRegions.put_primary(account, "eu-central")
    {:ok, _moved} = PlacerRegions.put_primary(account, "us-east")

    {:ok, eu_central} = Regions.fetch("eu-central")
    {:ok, us_east} = Regions.fetch("us-east")

    source_before = KubernetesController.manifest_revision(with_account(source, account), eu_central)
    destination_before = KubernetesController.manifest_revision(with_account(destination, account), us_east)

    {:ok, serving} = destination |> Server.observation_changeset(%{status: :active}) |> Repo.update()

    refute KubernetesController.manifest_revision(with_account(source, account), eu_central) == source_before
    refute KubernetesController.manifest_revision(with_account(serving, account), us_east) == destination_before
  end

  defp with_account(server, account), do: %{server | account: account}

  defp account do
    Accounts.get_account_from_user(AccountsFixtures.user_fixture())
  end

  defp instance(account, region, status \\ :active) do
    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: status,
      url: "https://#{account.name}-#{region}-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      provisioner_node_ref: "kura-#{account.id}-#{region}"
    })
  end

  defp manifest(account, server, region_id) do
    {:ok, region} = Regions.fetch(region_id)

    KubernetesController.manifest("kura-#{account.name}-#{region_id}", "0.5.2", account, region, server)
  end
end
