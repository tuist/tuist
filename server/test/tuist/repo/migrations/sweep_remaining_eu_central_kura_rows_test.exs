Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20260910150000_sweep_remaining_eu_central_kura_rows.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.SweepRemainingEuCentralKuraRowsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Kura.StorageRollup
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.SweepRemainingEuCentralKuraRows
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: AccountsFixtures.organization_fixture().account}
  end

  test "keeps the canonical rollup unchanged when the legacy account and day collide", %{account: account} do
    legacy = insert_rollup(account, "eu-central", ~D[2026-09-10], 9)
    canonical = insert_rollup(account, "eu-west", ~D[2026-09-10], 3)

    SweepRemainingEuCentralKuraRows.sweep_storage_rollups!(Repo)

    assert rollup(canonical.id) == canonical
    refute rollup(legacy.id)
  end

  test "preserves unmatched days, other accounts, and unrelated regions", %{account: account} do
    other_account = AccountsFixtures.organization_fixture().account
    canonical = insert_rollup(account, "eu-west", ~D[2026-09-10], 3)
    other_day = insert_rollup(account, "eu-central", ~D[2026-09-09], 5)
    other_tenant = insert_rollup(other_account, "eu-central", ~D[2026-09-10], 7)
    other_region = insert_rollup(account, "us-east", ~D[2026-09-10], 11)

    SweepRemainingEuCentralKuraRows.sweep_storage_rollups!(Repo)

    assert rollup(canonical.id) == canonical
    assert rollup(other_region.id) == other_region

    for rollup <- [other_day, other_tenant] do
      assert rollup(rollup.id) == %{rollup | region: "eu-west"}
    end
  end

  test "can run again after sweeping overlapping and unmatched rollups", %{account: account} do
    insert_rollup(account, "eu-central", ~D[2026-09-10], 9)
    canonical = insert_rollup(account, "eu-west", ~D[2026-09-10], 3)
    unmatched = insert_rollup(account, "eu-central", ~D[2026-09-09], 5)

    SweepRemainingEuCentralKuraRows.sweep_storage_rollups!(Repo)
    SweepRemainingEuCentralKuraRows.sweep_storage_rollups!(Repo)

    assert rollup(canonical.id) == canonical
    assert rollup(unmatched.id) == %{unmatched | region: "eu-west"}
  end

  defp rollup(id) do
    # excellent_migrations:safety-assured-for-next-line operation_get
    Repo.get(StorageRollup, id)
  end

  defp insert_rollup(account, region, date, count) do
    # excellent_migrations:safety-assured-for-next-line operation_insert
    Repo.insert!(%StorageRollup{
      account_id: account.id,
      region: region,
      date: date,
      eviction_count: count,
      evicted_bytes: count * 100,
      evicted_artifact_count: count * 2,
      min_shed_age_seconds: count,
      median_shed_age_seconds: count * 3,
      median_ring_span_seconds: count * 4,
      snapshot_count: count * 5,
      max_occupancy_percent: count,
      max_live_segment_bytes: count * 200,
      last_ring_budget_bytes: count * 300
    })
  end
end
