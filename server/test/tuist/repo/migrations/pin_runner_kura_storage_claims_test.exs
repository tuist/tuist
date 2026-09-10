Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20260910160000_pin_runner_kura_storage_claims.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.PinRunnerKuraStorageClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Accounts
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PinRunnerKuraStorageClaims
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "preserves live runner budgets without changing pinned, retired or volumeless instances" do
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

    assert reload(active).storage_claim_size == "50Gi"
    assert reload(provisioning).storage_claim_size == "50Gi"
    assert reload(failed).storage_claim_size == "50Gi"
    assert reload(pinned).storage_claim_size == "24Gi"
    assert reload(public).storage_claim_size == nil
    assert reload(retired).storage_claim_size == nil
    assert Enum.all?(volumeless, &(reload(&1).storage_claim_size == nil))
  end

  defp insert_server(region, attrs \\ []) do
    account = Accounts.get_account_from_user(AccountsFixtures.user_fixture())

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
