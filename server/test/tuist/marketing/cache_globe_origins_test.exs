defmodule Tuist.Marketing.CacheGlobeOriginsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.Origins
  alias Tuist.Kura.UsageEvent
  alias Tuist.Marketing.CacheGlobeLocations
  alias Tuist.Marketing.CacheGlobeOrigins
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "allocates each account's measured volume using its own runs, with resolutions only as a fallback" do
    windows =
      Enum.map([1, 4, 5], &[&1, "eu-west", ~N[2025-01-10 11:58:00], 60, 100]) ++
        Enum.map([2, 6, 7], &[&1, "us-west", ~N[2025-01-10 11:58:00], 60, 20]) ++
        [[3, "eu-west", ~N[2025-01-10 11:58:00], 60, 999]]

    rollups =
      Enum.flat_map([1, 4, 5], &[[&1, "DE", 3, 0], [&1, "FR", 1, 9999]]) ++
        Enum.flat_map([2, 6, 7], &[[&1, "US-CA", 0, 1], [&1, "US-NY", 0, 3]]) ++
        [[9, "JP", 1000, 1000]]

    origins = CacheGlobeOrigins.allocate(windows, rollups)
    assert length(origins) == 3
    assert Enum.find(origins, &(&1.location == CacheGlobeLocations.location("DE"))).downloads == 225
    assert Enum.find(origins, &(&1.location == CacheGlobeLocations.location("FR"))).downloads == 75
    assert Enum.find(origins, &(&1.region == "us-west")).downloads == 60
    assert Enum.sum(Enum.map(origins, & &1.downloads)) == 360
    assert Enum.all?(origins, &(&1.playback_delay_seconds == 300))
    assert Enum.all?(origins, &(&1.window_start == "2025-01-10T11:58:00Z" and &1.window_seconds == 60))
    assert origins == CacheGlobeOrigins.allocate(Enum.reverse(windows), Enum.reverse(rollups))

    assert Enum.all?(
             origins,
             &(&1 |> Map.keys() |> Enum.sort() == [
                 :downloads,
                 :location,
                 :playback_delay_seconds,
                 :region,
                 :window_seconds,
                 :window_start
               ])
           )
  end

  test "unknown or missing evidence is omitted without reassigning its share to known locations" do
    windows = Enum.map(1..3, &[&1, "eu-west", ~N[2025-01-10 11:58:00], 60, 100])
    rollups = Enum.flat_map(1..3, &[[&1, "DE", 1, 0], [&1, "XX", 1, 0]])
    assert [%{downloads: 150.0}] = CacheGlobeOrigins.allocate(windows, rollups)
    assert CacheGlobeOrigins.allocate(windows, []) == []
    assert CacheGlobeOrigins.allocate(windows, [[1, "DE", 0, 0]]) == []
    assert CacheGlobeLocations.location(nil) == nil
    assert CacheGlobeLocations.location("XX") == nil
    assert CacheGlobeLocations.location("US-CA") == CacheGlobeLocations.location("US")
  end

  test "merges accounts only after allocation, preserving distinct reporting windows and serving regions" do
    origins =
      CacheGlobeOrigins.allocate(
        Enum.flat_map(1..3, fn id ->
          [
            [id, "eu-west", ~N[2025-01-10 11:58:00], 60, 10],
            [id, "eu-west", ~N[2025-01-10 11:58:00], 60, 20],
            [id, "eu-west", ~N[2025-01-10 11:59:00], 60, 40],
            [id, "eu-east", ~N[2025-01-10 11:58:00], 120, 80]
          ]
        end),
        Enum.map(1..3, &[&1, "DE", 1, 0])
      )

    assert length(origins) == 3
    assert Enum.sum(Enum.map(origins, & &1.downloads)) == 450
    assert Enum.find(origins, &(&1.region == "eu-west" and &1.window_start == "2025-01-10T11:58:00Z")).downloads == 90
    assert Enum.find(origins, &(&1.region == "eu-east")).window_seconds == 120
    assert Enum.find(origins, &(&1.region == "eu-east")).playback_delay_seconds == 360
  end

  test "queries complete deduplicated public download windows and a bounded seven-date origin mix" do
    accounts = Enum.map(1..3, fn _ -> AccountsFixtures.user_fixture().account end)
    account = hd(accounts)
    other = AccountsFixtures.user_fixture().account

    rollups =
      Enum.flat_map(accounts, fn account ->
        [
          %{account_id: account.id, origin: "DE", date: ~D[2035-01-04], run_count: 3, demand_count: 0},
          %{account_id: account.id, origin: "FR", date: ~D[2035-01-10], run_count: 1, demand_count: 999},
          %{account_id: account.id, origin: "US", date: ~D[2035-01-03], run_count: 999, demand_count: 0},
          %{account_id: account.id, origin: "US", date: ~D[2035-01-11], run_count: 999, demand_count: 0}
        ]
      end)

    {:ok, _} =
      Origins.upsert_many(
        rollups ++
          [
            %{account_id: other.id, origin: "JP", date: ~D[2035-01-10], run_count: 999, demand_count: 0}
          ]
      )

    event = %{
      event_id: "globe-origin-window",
      account_id: account.id,
      project_id: 200,
      node_id: "private-node",
      region: "eu-west",
      traffic_plane: "public",
      direction: "egress",
      operation: "download",
      protocol: "http",
      artifact_kind: "xcframework",
      bytes: 2048,
      request_count: 100,
      window_start: ~N[2035-01-10 11:58:00],
      window_seconds: 60,
      inserted_at: ~N[2035-01-10 11:59:00]
    }

    events = [
      event,
      %{event | inserted_at: ~N[2035-01-10 11:59:01]},
      %{event | event_id: "origin-old", window_start: ~N[2035-01-10 11:40:00]},
      %{event | event_id: "origin-long", window_start: ~N[2035-01-10 11:54:00], window_seconds: 300, request_count: 40},
      %{event | event_id: "origin-future", window_start: ~N[2035-01-10 12:01:00]},
      %{event | event_id: "origin-incomplete", window_start: ~N[2035-01-10 11:59:59]},
      %{event | event_id: "origin-upload", operation: "upload", direction: "ingress"},
      %{event | event_id: "origin-peer", traffic_plane: "peer"},
      %{event | event_id: "origin-private", region: "scw-fr-par-runners"}
    ]

    replicas =
      accounts
      |> Enum.drop(1)
      |> Enum.flat_map(fn account ->
        [
          %{event | event_id: "origin-replica-#{account.id}", account_id: account.id},
          %{
            event
            | event_id: "origin-long-#{account.id}",
              account_id: account.id,
              window_start: ~N[2035-01-10 11:54:00],
              window_seconds: 300,
              request_count: 40
          }
        ]
      end)

    IngestRepo.insert_all(UsageEvent, events ++ replicas)

    origins = CacheGlobeOrigins.snapshot(~U[2035-01-10 12:00:00Z], ["eu-west"])
    assert length(origins) == 4
    assert Enum.sum(Enum.map(origins, & &1.downloads)) == 420
    minute = Enum.filter(origins, &(&1.window_seconds == 60))
    assert Enum.find(minute, &(&1.location == CacheGlobeLocations.location("DE"))).downloads == 225
    assert Enum.find(minute, &(&1.location == CacheGlobeLocations.location("FR"))).downloads == 75
    assert Enum.all?(Enum.filter(origins, &(&1.window_seconds == 300)), &(&1.playback_delay_seconds == 540))
    refute JSON.encode!(origins) =~ "private-node"
    refute JSON.encode!(origins) =~ "account_id"
    refute JSON.encode!(origins) =~ "project_id"
  end

  test "only publishes a cell with three distinct accounts in that country, region and reporting window" do
    window = [1, "eu-west", ~N[2035-01-10 11:58:00], 60, 37]
    rollups = Enum.map(1..3, &[&1, "IS", 1, 0])
    assert CacheGlobeOrigins.allocate([window], rollups) == []
    assert CacheGlobeOrigins.allocate([window, window, window], rollups) == []
    two = [window, List.replace_at(window, 0, 2)]
    assert CacheGlobeOrigins.allocate(two, rollups) == []
    third = List.replace_at(window, 0, 3)
    assert CacheGlobeOrigins.allocate(two ++ [List.replace_at(third, 2, ~N[2035-01-10 11:59:00])], rollups) == []
    assert [%{downloads: 111.0}] = CacheGlobeOrigins.allocate(two ++ [third], rollups)
  end

  test "different accounts' origin distributions are not pooled before weighting their downloads" do
    windows = [
      [1, "eu-west", ~N[2035-01-10 11:58:00], 60, 100],
      [2, "eu-west", ~N[2035-01-10 11:58:00], 60, 60],
      [3, "eu-west", ~N[2035-01-10 11:58:00], 60, 120]
    ]

    rollups = [[1, "DE", 3, 0], [1, "FR", 1, 0], [2, "DE", 1, 0], [2, "FR", 3, 0], [3, "DE", 2, 0], [3, "FR", 2, 0]]
    origins = CacheGlobeOrigins.allocate(windows, rollups)
    assert Enum.find(origins, &(&1.location == CacheGlobeLocations.location("DE"))).downloads == 150
    assert Enum.find(origins, &(&1.location == CacheGlobeLocations.location("FR"))).downloads == 130
  end

  test "negligible contributors and multiple rows or subdivisions cannot disguise a dominant account" do
    windows = Enum.map(1..3, &[&1, "eu-west", ~N[2035-01-10 11:58:00], 60, 1000])
    rollups = [[1, "IS", 1, 0], [2, "IS", 1, 0], [2, "SE", 9999, 0], [3, "IS", 1, 0], [3, "SE", 9999, 0]]
    assert CacheGlobeOrigins.allocate(windows, rollups) == []

    rollups = [[1, "US-CA", 1, 0], [1, "US-NY", 1, 0], [2, "US", 1, 0], [3, "US", 1, 0]]
    dominant = [hd(windows), hd(windows), hd(windows)] ++ Enum.drop(windows, 1)
    assert CacheGlobeOrigins.allocate(dominant, rollups) == []
    assert [%{downloads: 4000.0}] = CacheGlobeOrigins.allocate([hd(windows) | windows], rollups)
  end

  test "released cells are immutable across late reports and changed origin mixes" do
    windows = Enum.map(1..4, &[&1, "eu-west", ~N[2035-01-10 11:58:00], 60, 37])
    rollups = Enum.map(1..4, &[&1, "IS", 1, 0])
    original = CacheGlobeOrigins.allocate(Enum.take(windows, 3), rollups)
    assert [%{downloads: 111.0}] = original
    initialized = CacheGlobeOrigins.freeze(nil, [], "2035-01-10T11:50:00Z")
    released = CacheGlobeOrigins.freeze(initialized, original, "2035-01-10T12:00:00Z")
    late = CacheGlobeOrigins.allocate(windows, rollups)
    assert [%{downloads: 148.0}] = late
    next = CacheGlobeOrigins.freeze(released, late, "2035-01-10T12:01:00Z")
    assert next.origins == original
    assert CacheGlobeOrigins.freeze(next, [], "2035-01-10T12:02:00Z").origins == original
    assert CacheGlobeOrigins.freeze(next, [], "2035-01-10T12:15:00Z").origins == []
  end

  test "journal loss never re-releases old cells, while later windows can warm up again" do
    origin = %{
      location: [65.0, -19.0],
      region: "eu-west",
      window_start: "2035-01-10T11:58:00Z",
      window_seconds: 60,
      playback_delay_seconds: 300,
      downloads: 111.0
    }

    reset = CacheGlobeOrigins.freeze(nil, [origin], "2035-01-10T12:00:00Z")
    assert reset.origins == []
    assert CacheGlobeOrigins.freeze(reset, [origin], "2035-01-10T12:01:00Z").origins == []
    future = %{origin | window_start: "2035-01-10T12:00:00Z"}
    assert CacheGlobeOrigins.freeze(reset, [future], "2035-01-10T12:02:00Z").origins == [future]
  end

  test "origin query failures are optional and enforce read and result bounds" do
    expect(ClickHouseRepo, :query, fn _query, params, opts ->
      assert params["regions"] == ["eu-west"]
      assert params["since"] == ~N[2035-01-10 11:44:00]
      assert opts[:settings][:max_rows_to_read] == 5_000_000
      assert opts[:settings][:max_result_rows] == 25_000
      assert opts[:settings][:result_overflow_mode] == "throw"
      {:error, %Ch.Error{message: "Row read limit exceeded"}}
    end)

    reject(Repo, :transaction, 1)

    assert capture_log(fn ->
             assert CacheGlobeOrigins.snapshot(~U[2035-01-10 12:00:00Z], ["eu-west"]) == []
           end) =~ "origin estimates unavailable"
  end

  test "no usage windows avoids PostgreSQL reads" do
    expect(ClickHouseRepo, :query, fn _query, _params, _opts -> {:ok, %{rows: []}} end)
    reject(Repo, :transaction, 1)
    assert CacheGlobeOrigins.snapshot(~U[2035-01-10 12:00:00Z], ["eu-west"]) == []
  end

  test "too many PostgreSQL origins omits estimates rather than publishing a biased subset" do
    expect(ClickHouseRepo, :query, fn _query, _params, _opts ->
      {:ok, %{rows: [[1, "eu-west", ~N[2035-01-10 11:58:00], 60, 10]]}}
    end)

    expect(Repo, :transaction, fn _callback -> {:error, :row_limit} end)

    assert capture_log(fn ->
             assert CacheGlobeOrigins.snapshot(~U[2035-01-10 12:00:00Z], ["eu-west"]) == []
           end) =~ "origin estimates unavailable"
  end

  test "public expansion has a bounded payload and does not publish a truncated allocation" do
    windows =
      Enum.map(0..10_000, fn index ->
        [1, "eu-west", NaiveDateTime.add(~N[2035-01-10 00:00:00], index, :second), 60, 1]
      end)

    assert capture_log(fn ->
             assert CacheGlobeOrigins.allocate(windows, [[1, "DE", 1, 0]]) == []
           end) =~ "public window limit"
  end

  test "PostgreSQL unavailability leaves the origin estimates empty" do
    expect(ClickHouseRepo, :query, fn _query, _params, _opts ->
      {:ok, %{rows: [[1, "eu-west", ~N[2035-01-10 11:58:00], 60, 10]]}}
    end)

    expect(Repo, :transaction, fn _callback -> raise DBConnection.ConnectionError, message: "Unavailable" end)

    assert capture_log(fn ->
             assert CacheGlobeOrigins.snapshot(~U[2035-01-10 12:00:00Z], ["eu-west"]) == []
           end) =~ "origin estimates unavailable"
  end
end
