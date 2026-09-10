Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20260910160000_pin_runner_kura_storage_claims.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.PinRunnerKuraStorageClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Accounts
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PinRunnerKuraStorageClaims
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "enrolls live runner budgets immediately without changing pinned, retired or volumeless instances" do
    active = insert_server("scw-fr-par-runners")
    provisioning = insert_server("scw-fr-par-runners", status: :provisioning)
    failed = insert_server("scw-fr-par-runners", status: :failed)
    pinned = insert_server("scw-fr-par-runners", storage_claim_size: "24Gi")
    public = insert_server("us-east")
    retired = insert_server("hetzner-staging-runners")

    volumeless =
      for status <- [:destroying, :destroyed, :archived], do: insert_server("scw-fr-par-runners", status: status)

    PinRunnerKuraStorageClaims.pin_existing_claims!(Repo)
    PinRunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert reload(active).storage_claim_size == "8Gi"
    assert reload(provisioning).storage_claim_size == "8Gi"
    assert reload(failed).storage_claim_size == "8Gi"
    assert reload(pinned).storage_claim_size == "24Gi"
    assert reload(public).storage_claim_size == nil
    assert reload(retired).storage_claim_size == nil
    assert Enum.all?(volumeless, &(reload(&1).storage_claim_size == nil))
  end

  test "uses the latest eligible plan unless the account already has a sized claim" do
    enterprise = account()
    BillingFixtures.subscription_fixture(account_id: enterprise.id, plan: :enterprise, status: "trialing")
    BillingFixtures.subscription_fixture(account_id: enterprise.id, plan: :pro, status: "canceled")
    pro = account()
    BillingFixtures.subscription_fixture(account_id: pro.id, plan: :enterprise, inserted_at: ~U[2026-01-01 00:00:00Z])
    BillingFixtures.subscription_fixture(account_id: pro.id, plan: :pro)
    sized = account()
    :ok = PlacerClaims.put(sized, "24Gi")
    servers = for a <- [enterprise, pro, sized], do: insert_server("scw-fr-par-runners", account: a)

    PinRunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert Enum.map(servers, &reload(&1).storage_claim_size) == ["16Gi", "8Gi", "24Gi"]
  end

  test "caps enrollment at the old budget across supported quantity units" do
    claims = ["64Gi", "1Ti", "51200Mi", "24576Mi", "25165824Ki", "25769803776"]

    servers =
      for claim <- claims do
        a = account()
        :ok = PlacerClaims.put(a, claim)
        insert_server("scw-fr-par-runners", account: a)
      end

    PinRunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert Enum.map(servers, &reload(&1).storage_claim_size) ==
             ["50Gi", "50Gi", "51200Mi", "24576Mi", "25165824Ki", "25769803776"]
  end

  defp account, do: Accounts.get_account_from_user(AccountsFixtures.user_fixture())

  defp insert_server(region, attrs \\ []) do
    account = Keyword.get_lazy(attrs, :account, &account/0)

    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: Keyword.get(attrs, :status, :active),
      provisioner_node_ref: "kura-#{account.id}-#{region}",
      storage_claim_size: Keyword.get(attrs, :storage_claim_size)
    })
  end

  # excellent_migrations:safety-assured-for-next-line operation_get
  defp reload(%Server{id: id}), do: Repo.get!(Server, id)
end
