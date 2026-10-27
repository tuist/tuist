Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261016120000_pin_ber1_runner_kura_storage_claims.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.PinBer1RunnerKuraStorageClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Accounts
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PinBer1RunnerKuraStorageClaims
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "pins each rack cache at the largest claim its account's other instances hold" do
    account = account()
    insert_server("us-east", account: account, storage_claim_size: "64Gi")
    insert_server("eu-west", account: account, storage_claim_size: "100Gi")
    insert_server("us-west", account: account, storage_claim_size: "512Gi", status: :archived)
    insert_server("scw-fr-par-runners", account: account, storage_claim_size: "broken")
    :ok = PlacerClaims.put(account, "32Gi")
    rack = insert_server("ber1-runners", account: account)

    PinBer1RunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert reload(rack).storage_claim_size == "100Gi"
    assert PlacerClaims.effective_claim_size(account) == "100Gi"
  end

  test "falls back to the sized claim, then the plan's starting claim" do
    sized = account()
    :ok = PlacerClaims.put(sized, "24Gi")
    enterprise = account()
    BillingFixtures.subscription_fixture(account_id: enterprise.id, plan: :enterprise, status: "past_due")
    pro = account()
    BillingFixtures.subscription_fixture(account_id: pro.id, plan: :pro)
    servers = for a <- [sized, enterprise, pro], do: insert_server("ber1-runners", account: a)

    PinBer1RunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert Enum.map(servers, &reload(&1).storage_claim_size) == ["24Gi", "16Gi", "8Gi"]
  end

  test "leaves pinned, volumeless and other regions' instances alone" do
    pinned = insert_server("ber1-runners", storage_claim_size: "50Gi")
    archived = insert_server("ber1-runners", status: :archived)
    public = insert_server("us-east")

    PinBer1RunnerKuraStorageClaims.pin_existing_claims!(Repo)
    PinBer1RunnerKuraStorageClaims.pin_existing_claims!(Repo)

    assert reload(pinned).storage_claim_size == "50Gi"
    assert reload(archived).storage_claim_size == nil
    assert reload(public).storage_claim_size == nil
  end

  test "rejects an unsupported sized claim without pinning any of the batch" do
    valid = insert_server("ber1-runners")
    invalid_account = account()
    invalid = insert_server("ber1-runners", account: invalid_account)
    :ok = PlacerClaims.put(invalid_account, "24Gi")
    # excellent_migrations:safety-assured-for-next-line operation_query
    Repo.query!("UPDATE kura_placer_claims SET claim_size = '24G' WHERE account_id = $1", [invalid_account.id])

    assert_raise ArgumentError, ~r/invalid storage claim.*repair before pinning/, fn ->
      PinBer1RunnerKuraStorageClaims.pin_existing_claims!(Repo)
    end

    assert reload(valid).storage_claim_size == nil
    assert reload(invalid).storage_claim_size == nil
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
