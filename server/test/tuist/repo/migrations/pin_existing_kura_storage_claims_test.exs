Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20260826120000_pin_existing_kura_storage_claims.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.PinExistingKuraStorageClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PinExistingKuraStorageClaims
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    :ok
  end

  test "pins unpinned governed instances at what their plan rendered before the ladder came down" do
    enterprise = account(:enterprise)
    pro = account(:pro)
    air = account(nil)

    enterprise_server = insert_server(enterprise, "us-east")
    pro_server = insert_server(pro, "eu-central")
    air_server = insert_server(air, "us-west")

    # Already pinned: whatever it holds is what its volume was built at.
    pinned = insert_server(enterprise, "ap-southeast", storage_claim_size: "200Gi")

    # Not storage-governed, so its claim comes from the region rather than the
    # account, and pinning it would override that.
    runner_cache = insert_server(enterprise, "scw-fr-par-runners")

    # Holds no volume, so it takes the current claim when next built.
    archived = insert_server(enterprise, "ca-east", status: :archived)

    PinExistingKuraStorageClaims.pin_existing_claims!(Repo)

    assert reload(enterprise_server).storage_claim_size == "50Gi"
    assert reload(pro_server).storage_claim_size == "30Gi"
    assert reload(air_server).storage_claim_size == "8Gi"

    assert reload(pinned).storage_claim_size == "200Gi"
    assert reload(runner_cache).storage_claim_size == nil
    assert reload(archived).storage_claim_size == nil
  end

  defp account(plan) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    if plan, do: BillingFixtures.subscription_fixture(account_id: account.id, plan: plan)
    account
  end

  defp insert_server(account, region, attrs \\ []) do
    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: Keyword.get(attrs, :status, :active),
      provisioner_node_ref: "kura-#{account.id}-#{region}-#{System.unique_integer([:positive])}",
      storage_claim_size: Keyword.get(attrs, :storage_claim_size)
    })
  end

  # excellent_migrations:safety-assured-for-next-line operation_get
  defp reload(%Server{id: id}), do: Repo.get!(Server, id)
end
