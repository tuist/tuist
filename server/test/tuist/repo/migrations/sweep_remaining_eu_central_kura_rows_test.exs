Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260910150000_sweep_remaining_eu_central_kura_rows.exs",
    __DIR__
  )
)

defmodule Tuist.Repo.Migrations.SweepRemainingEuCentralKuraRowsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Kura.StorageRollup
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.SweepRemainingEuCentralKuraRows
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "preserves canonical aggregates, renames non-conflicting rows and can run twice" do
    account = AccountsFixtures.organization_fixture().account
    another = AccountsFixtures.organization_fixture().account
    date = ~D[2026-09-10]
    insert_rollup(account.id, "eu-central", date, 10)
    canonical = insert_rollup(account.id, "eu-west", date, 20)
    earlier = insert_rollup(account.id, "eu-central", Date.add(date, -1), 30)
    other_account = insert_rollup(another.id, "eu-central", date, 40)
    other_region = insert_rollup(account.id, "us-east", date, 50)

    for _ <- 1..2 do
      SweepRemainingEuCentralKuraRows.sweep_storage_rollups!(Repo)

      assert Repo.get!(StorageRollup, canonical.id) == canonical
      assert Repo.get!(StorageRollup, earlier.id) == %{earlier | region: "eu-west"}
      assert Repo.get!(StorageRollup, other_account.id) == %{other_account | region: "eu-west"}
      assert Repo.get!(StorageRollup, other_region.id) == other_region
      refute Repo.get_by(StorageRollup, account_id: account.id, region: "eu-central", date: date)
    end
  end

  defp insert_rollup(account_id, region, date, count) do
    Repo.insert!(%StorageRollup{
      account_id: account_id,
      region: region,
      date: date,
      eviction_count: count,
      snapshot_count: count * 2,
      median_shed_age_seconds: count * 3
    })
  end
end
