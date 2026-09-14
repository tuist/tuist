defmodule Tuist.Kura.StorageRollupsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Kura.EvictionEvent
  alias Tuist.Kura.StorageRollups
  alias Tuist.Kura.StorageSnapshot
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: AccountsFixtures.organization_fixture().account}
  end

  # ClickHouse rows survive across tests (no sandbox), so every test claims
  # its own calendar day: a refresh over that day sees only this test's rows.
  defp unique_date do
    Date.add(~D[2030-01-01], rem(System.unique_integer([:positive]), 20_000))
  end

  defp at(date, time), do: NaiveDateTime.new!(date, time)

  describe "refresh/1" do
    test "merges eviction and snapshot aggregates into one row per account-region-day", %{account: account} do
      date = unique_date()
      insert_eviction(account.id, "evict-1-#{account.id}", at(date, ~T[10:00:00]))
      insert_snapshot(account.id, "snap-1-#{account.id}", at(date, ~T[12:00:00]))

      {:ok, 1} = StorageRollups.refresh([date])

      assert [rollup] = StorageRollups.for_account(account, date)
      assert rollup.region == "us-east"
      assert rollup.date == date
      assert rollup.eviction_count == 1
      assert rollup.median_shed_age_seconds == 3_600
      assert rollup.median_ring_span_seconds == 7_200
      assert rollup.snapshot_count == 1
      assert rollup.max_occupancy_percent == 50
      assert rollup.max_live_segment_bytes == 5_368_709_120
      assert rollup.last_ring_budget_bytes == 10_737_418_240
    end

    test "a refresh converges the same day instead of duplicating it", %{account: account} do
      date = unique_date()
      insert_eviction(account.id, "evict-1-#{account.id}", at(date, ~T[10:00:00]))

      {:ok, 1} = StorageRollups.refresh([date])

      insert_eviction(account.id, "evict-2-#{account.id}", at(date, ~T[15:00:00]))

      {:ok, 1} = StorageRollups.refresh([date])

      assert [rollup] = StorageRollups.for_account(account, date)
      assert rollup.eviction_count == 2
    end

    test "days with only snapshots produce rows with no eviction signal", %{account: account} do
      date = unique_date()
      insert_snapshot(account.id, "snap-1-#{account.id}", at(date, ~T[12:00:00]))

      {:ok, 1} = StorageRollups.refresh([date])

      assert [rollup] = StorageRollups.for_account(account, date)
      assert rollup.eviction_count == 0
      assert rollup.median_shed_age_seconds == nil
      assert rollup.snapshot_count == 1
    end

    test "rolls a batch delivered days late onto the day it happened", %{account: account} do
      # The node was holding this eviction while the control plane was
      # unreachable, so it arrives now stamped with the day it happened.
      happened = unique_date()
      delivered = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      insert_eviction(account.id, "evict-late-#{account.id}", at(happened, ~T[10:00:00]), delivered)

      {:ok, 1} = StorageRollups.refresh([happened])

      assert [rollup] = StorageRollups.for_account(account, happened)
      assert rollup.date == happened
      assert rollup.eviction_count == 1
    end

    test "telemetry for accounts that no longer exist is dropped" do
      date = unique_date()
      ghost_id = System.unique_integer([:positive]) + 5_000_000
      insert_eviction(ghost_id, "evict-ghost-#{ghost_id}", at(date, ~T[10:00:00]))

      assert {:ok, 0} = StorageRollups.refresh([date])
    end
  end

  describe "for_account/2" do
    test "returns only rows on or after the cutoff, oldest first", %{account: account} do
      early = unique_date()
      late = Date.add(early, 10)
      insert_eviction(account.id, "evict-old-#{account.id}", at(early, ~T[10:00:00]))
      insert_eviction(account.id, "evict-new-#{account.id}", at(late, ~T[10:00:00]))

      {:ok, _count} = StorageRollups.refresh([early, late])

      assert [rollup] = StorageRollups.for_account(account, Date.add(early, 5))
      assert rollup.date == late
    end
  end

  defp insert_eviction(account_id, event_id, evicted_at, inserted_at \\ nil) do
    IngestRepo.insert_all(EvictionEvent, [
      %{
        event_id: event_id,
        account_id: account_id,
        node_id: "kura-0",
        region: "us-east",
        segment_id: "segment-#{event_id}",
        reason: "capacity",
        evicted_at: evicted_at,
        segment_created_at: NaiveDateTime.add(evicted_at, -7_200),
        newest_content_at: NaiveDateTime.add(evicted_at, -3_600),
        artifact_count: 5,
        bytes: 536_870_912,
        inserted_at: inserted_at || evicted_at
      }
    ])
  end

  defp insert_snapshot(account_id, event_id, captured_at, inserted_at \\ nil) do
    IngestRepo.insert_all(StorageSnapshot, [
      %{
        event_id: event_id,
        account_id: account_id,
        node_id: "kura-0",
        region: "us-east",
        captured_at: captured_at,
        ring_budget_bytes: 10_737_418_240,
        desired_segment_count: 20,
        live_segment_count: 10,
        live_segment_bytes: 5_368_709_120,
        oldest_segment_created_at: ~N[2026-08-19 00:00:00],
        newest_content_at: ~N[2026-08-20 00:00:00],
        inserted_at: inserted_at || captured_at
      }
    ])
  end
end
