defmodule Tuist.Kura.StorageTelemetryTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.EvictionEvent
  alias Tuist.Kura.StorageSnapshot
  alias Tuist.Kura.StorageTelemetry
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp eviction_payload(attrs) do
    Map.merge(
      %{
        "event_id" => "evict-#{System.unique_integer([:positive])}",
        "tenant_id" => "acme",
        "node_id" => "kura-0",
        "region" => "us-east",
        "segment_id" => "segment-1",
        "reason" => "capacity",
        "evicted_at_unix_ms" => 1_777_000_000_000,
        "segment_created_at_unix_ms" => 1_776_900_000_000,
        "newest_content_at_unix_ms" => 1_776_950_000_000,
        "artifact_count" => 12,
        "bytes" => 536_870_912
      },
      attrs
    )
  end

  defp snapshot_payload(attrs) do
    Map.merge(
      %{
        "event_id" => "snapshot-#{System.unique_integer([:positive])}",
        "tenant_id" => "acme",
        "node_id" => "kura-0",
        "region" => "us-east",
        "captured_at_unix_ms" => 1_777_000_000_000,
        "ring_budget_bytes" => 26_843_545_600,
        "desired_segment_count" => 50,
        "live_segment_count" => 10,
        "live_segment_bytes" => 5_368_709_120,
        "oldest_segment_created_at_unix_ms" => 1_776_900_000_000,
        "newest_content_at_unix_ms" => 1_776_950_000_000
      },
      attrs
    )
  end

  describe "create_eviction_events/1" do
    test "resolves the tenant handle to an account id and persists the row" do
      handle = "acme-#{System.unique_integer([:positive])}"
      account = AccountsFixtures.organization_fixture(name: handle).account

      {:ok, 1} =
        StorageTelemetry.create_eviction_events([
          eviction_payload(%{"event_id" => "wire-evict-1", "tenant_id" => handle})
        ])

      row = ClickHouseRepo.one(from(e in EvictionEvent, where: e.event_id == "wire-evict-1"))

      assert row.account_id == account.id
      assert row.segment_id == "segment-1"
      assert row.reason == "capacity"
      assert row.evicted_at == ~N[2026-04-24 03:06:40]
      assert row.newest_content_at == ~N[2026-04-23 13:13:20]
      assert row.artifact_count == 12
      assert row.bytes == 536_870_912
    end

    test "an unknown tenant drops to account 0 rather than failing the batch" do
      {:ok, 1} =
        StorageTelemetry.create_eviction_events([
          eviction_payload(%{"event_id" => "wire-evict-2", "tenant_id" => "nobody-knows-this"})
        ])

      row = ClickHouseRepo.one(from(e in EvictionEvent, where: e.event_id == "wire-evict-2"))
      assert row.account_id == 0
    end

    test "rejects oversized batches" do
      events = Enum.map(1..5_001, fn index -> eviction_payload(%{"event_id" => "evict-#{index}"}) end)

      assert StorageTelemetry.create_eviction_events(events) == {:error, :too_many_events}
    end
  end

  describe "create_storage_snapshots/1" do
    test "persists the occupancy snapshot with the resolved account" do
      handle = "acme-#{System.unique_integer([:positive])}"
      account = AccountsFixtures.organization_fixture(name: handle).account

      {:ok, 1} =
        StorageTelemetry.create_storage_snapshots([
          snapshot_payload(%{"event_id" => "wire-snapshot-1", "tenant_id" => handle})
        ])

      row = ClickHouseRepo.one(from(s in StorageSnapshot, where: s.event_id == "wire-snapshot-1"))

      assert row.account_id == account.id
      assert row.ring_budget_bytes == 26_843_545_600
      assert row.live_segment_bytes == 5_368_709_120
      assert row.desired_segment_count == 50
    end

    test "an absent oldest-segment timestamp lands as the epoch" do
      {:ok, 1} =
        StorageTelemetry.create_storage_snapshots([
          snapshot_payload(%{
            "event_id" => "wire-snapshot-2",
            "live_segment_count" => 0,
            "live_segment_bytes" => 0,
            "oldest_segment_created_at_unix_ms" => nil,
            "newest_content_at_unix_ms" => nil
          })
        ])

      row = ClickHouseRepo.one(from(s in StorageSnapshot, where: s.event_id == "wire-snapshot-2"))
      assert row.oldest_segment_created_at == ~N[1970-01-01 00:00:00]
    end
  end

  # ClickHouse rows are not sandboxed per test, so every test scopes itself
  # to a unique account id and filters the global aggregates down to it.
  defp for_account(aggregates, account_id), do: Enum.filter(aggregates, &(&1.account_id == account_id))

  describe "eviction_day_aggregates/2" do
    test "aggregates shed ages per account, region, and day with event dedup" do
      account_id = System.unique_integer([:positive]) + 1_000_000

      insert_eviction_rows([
        # Redelivered event: must count once, or the median would move.
        eviction_row(account_id, "dup-#{account_id}", ~N[2026-08-20 10:00:00], 3_600, 7_200,
          inserted_at: ~N[2026-08-20 10:01:00]
        ),
        eviction_row(account_id, "dup-#{account_id}", ~N[2026-08-20 10:00:00], 3_600, 7_200,
          inserted_at: ~N[2026-08-20 10:05:00]
        ),
        eviction_row(account_id, "solo-1-#{account_id}", ~N[2026-08-20 12:00:00], 7_200, 10_800, []),
        eviction_row(account_id, "solo-2-#{account_id}", ~N[2026-08-20 14:00:00], 10_800, 14_400, []),
        # A different day lands in its own bucket.
        eviction_row(account_id, "solo-3-#{account_id}", ~N[2026-08-21 09:00:00], 1_800, 3_600, [])
      ])

      aggregates =
        ~D[2026-08-20]
        |> StorageTelemetry.eviction_day_aggregates(~D[2026-08-21])
        |> for_account(account_id)

      by_date = Map.new(aggregates, &{&1.date, &1})

      first = by_date[~D[2026-08-20]]
      assert first.account_id == account_id
      assert first.region == "us-east"
      assert first.eviction_count == 3
      assert first.min_shed_age_seconds == 3_600
      assert first.median_shed_age_seconds == 7_200
      assert first.median_ring_span_seconds == 10_800

      second = by_date[~D[2026-08-21]]
      assert second.eviction_count == 1
      assert second.median_shed_age_seconds == 1_800
    end

    test "ignores non-capacity evictions and unattributable accounts" do
      account_id = System.unique_integer([:positive]) + 1_000_000

      insert_eviction_rows([
        eviction_row(account_id, "admin-#{account_id}", ~N[2026-08-20 10:00:00], 3_600, 7_200, reason: "admin"),
        eviction_row(0, "unattributed-#{account_id}", ~N[2026-08-20 10:00:00], 3_600, 7_200, [])
      ])

      aggregates =
        ~D[2026-08-20]
        |> StorageTelemetry.eviction_day_aggregates(~D[2026-08-20])
        |> Enum.filter(&(&1.account_id in [account_id, 0]))

      assert aggregates == []
    end
  end

  describe "snapshot_day_aggregates/2" do
    test "reports the day's peak occupancy and latest budget" do
      account_id = System.unique_integer([:positive]) + 1_000_000

      insert_snapshot_rows([
        snapshot_row(account_id, "snap-1-#{account_id}", ~N[2026-08-20 08:00:00], 10_737_418_240, 2_147_483_648, []),
        snapshot_row(account_id, "snap-2-#{account_id}", ~N[2026-08-20 20:00:00], 10_737_418_240, 4_294_967_296, []),
        # Redelivery of the same snapshot window.
        snapshot_row(account_id, "snap-2-#{account_id}", ~N[2026-08-20 20:00:00], 10_737_418_240, 4_294_967_296,
          inserted_at: ~N[2026-08-20 20:05:00]
        )
      ])

      assert [aggregate] =
               ~D[2026-08-20]
               |> StorageTelemetry.snapshot_day_aggregates(~D[2026-08-20])
               |> for_account(account_id)

      assert aggregate.account_id == account_id
      assert aggregate.date == ~D[2026-08-20]
      assert aggregate.snapshot_count == 2
      assert aggregate.max_occupancy_percent == 40
      assert aggregate.max_live_segment_bytes == 4_294_967_296
      assert aggregate.last_ring_budget_bytes == 10_737_418_240
    end
  end

  defp eviction_row(account_id, event_id, evicted_at, shed_age_seconds, span_seconds, attrs) do
    attrs = Map.new(attrs)

    %{
      event_id: event_id,
      account_id: account_id,
      node_id: "kura-0",
      region: "us-east",
      segment_id: "segment-#{event_id}",
      reason: Map.get(attrs, :reason, "capacity"),
      evicted_at: evicted_at,
      segment_created_at: NaiveDateTime.add(evicted_at, -span_seconds),
      newest_content_at: NaiveDateTime.add(evicted_at, -shed_age_seconds),
      artifact_count: 10,
      bytes: 536_870_912,
      inserted_at: Map.get(attrs, :inserted_at, evicted_at)
    }
  end

  defp insert_eviction_rows(rows) do
    IngestRepo.insert_all(EvictionEvent, rows)
  end

  defp snapshot_row(account_id, event_id, captured_at, budget_bytes, live_bytes, attrs) do
    attrs = Map.new(attrs)

    %{
      event_id: event_id,
      account_id: account_id,
      node_id: "kura-0",
      region: "us-east",
      captured_at: captured_at,
      ring_budget_bytes: budget_bytes,
      desired_segment_count: 20,
      live_segment_count: 4,
      live_segment_bytes: live_bytes,
      oldest_segment_created_at: ~N[2026-08-19 00:00:00],
      newest_content_at: ~N[2026-08-20 00:00:00],
      inserted_at: Map.get(attrs, :inserted_at, captured_at)
    }
  end

  defp insert_snapshot_rows(rows) do
    IngestRepo.insert_all(StorageSnapshot, rows)
  end
end
