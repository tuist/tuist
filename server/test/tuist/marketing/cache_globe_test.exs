defmodule Tuist.Marketing.CacheGlobeTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.Build
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.CacheGlobeOrigins
  alias Tuist.ReapiCache.CacheEvent
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures

  setup do
    stub(CacheGlobeOrigins, :snapshot, fn _now, _regions -> [] end)
    :ok
  end

  test "only released origins contribute observation status without changing measured totals" do
    origins = [
      %{
        location: [51.17, 10.45],
        region: "eu-west",
        downloads: 100.0,
        window_start: "1999-12-31T23:59:00Z",
        window_seconds: 60
      }
    ]

    expect(CacheGlobeOrigins, :snapshot, fn now, regions ->
      assert now == ~U[2000-01-01 00:01:00Z]
      assert regions == Enum.map(CacheGlobe.empty().regions, & &1.id)
      origins
    end)

    snapshot = CacheGlobe.snapshot(~U[2000-01-01 00:01:00.123456Z])
    assert snapshot.origins == origins
    assert snapshot.playback_delay_seconds == 300
    assert snapshot.status == :waiting
    assert snapshot.observed_at == nil
    assert snapshot.downloads == 0
    assert Enum.all?(snapshot.regions, &(&1.downloads == 0))

    withheld = CacheGlobe.with_origins(snapshot, [])
    assert withheld.status == :waiting
    assert withheld.observed_at == nil

    released = CacheGlobe.with_origins(snapshot, origins)
    assert released.status == :available
    assert released.observed_at == "2000-01-01T00:00:00Z"
    assert released.downloads == 0
    assert Enum.all?(released.regions, &(&1.downloads == 0))
  end

  test "counts delivered requests, deduplicates retries, and exposes only public regional totals" do
    event = %{
      event_id: "globe-download",
      account_id: 100,
      project_id: 200,
      node_id: "private-node",
      region: "eu-west",
      traffic_plane: "public",
      direction: "egress",
      operation: "download",
      protocol: "http",
      artifact_kind: "xcframework",
      bytes: 2048,
      request_count: 5,
      window_start: ~N[2025-01-10 11:58:00],
      window_seconds: 60,
      inserted_at: ~N[2025-01-10 11:59:00]
    }

    IngestRepo.insert_all(UsageEvent, [
      event,
      %{event | inserted_at: ~N[2025-01-10 11:59:01]},
      %{event | event_id: "globe-old", window_start: ~N[2025-01-10 10:00:00]},
      %{event | event_id: "globe-south-america", region: "sa-west"},
      %{event | event_id: "globe-yesterday", window_start: ~N[2025-01-09 23:59:00]},
      %{event | event_id: "globe-future", window_start: ~N[2025-01-10 12:01:00]},
      %{event | event_id: "globe-upload", operation: "upload", direction: "ingress"},
      %{event | event_id: "globe-peer", traffic_plane: "peer"},
      %{event | event_id: "globe-private", region: "scw-fr-par-runners"},
      %{event | event_id: "globe-unknown", region: "unknown"}
    ])

    snapshot = CacheGlobe.snapshot(~U[2025-01-10 12:00:00.123456Z])

    assert snapshot.downloads == 15
    assert snapshot.bytes == 6144
    assert snapshot.recent_downloads == 10
    assert snapshot.recent_bytes == 4096
    assert snapshot.observed_at == "2025-01-10T11:59:00Z"
    assert Enum.find(snapshot.regions, &(&1.id == "eu-west")).downloads == 10
    assert Enum.find(snapshot.regions, &(&1.id == "sa-west")).downloads == 5
    assert Enum.find(snapshot.regions, &(&1.id == "sa-west")).recent_downloads == 5
    refute JSON.encode!(snapshot) =~ "private-node"
    refute JSON.encode!(snapshot) =~ "account_id"
    refute JSON.encode!(snapshot) =~ "project_id"
  end

  test "no reports is a waiting state, not a fabricated live counter" do
    snapshot = CacheGlobe.snapshot(~U[2001-01-01 12:00:00Z])
    assert snapshot.status == :waiting
    assert snapshot.downloads == 0
    assert snapshot.recent_bytes == 0
    assert snapshot.observed_at == nil
    assert Enum.all?(snapshot.regions, &(&1.recent_downloads == 0))
    assert snapshot.breakdown == %{"all" => nil, "module" => nil, "gradle" => nil, "bazel" => nil}
  end

  test "hit rates use today's lookups and weight the overall rate by opportunities" do
    now = ~U[2030-01-10 12:00:00Z]
    reported_at = ~N[2030-01-10 11:00:00]

    CommandEventsFixtures.command_event_fixture(
      created_at: now,
      ran_at: reported_at,
      cacheable_targets: Enum.map(1..10, &"Target#{&1}"),
      local_cache_target_hits: ["Target1"],
      remote_cache_target_hits: ["Target2", "Target3"]
    )

    for {name, timestamp} <- [
          {"cache", reported_at},
          {"generate", ~N[2030-01-09 23:59:00]},
          {"generate", ~N[2030-01-10 12:00:00]}
        ] do
      CommandEventsFixtures.command_event_fixture(
        name: name,
        created_at: now,
        ran_at: timestamp,
        cacheable_targets: ["Excluded"],
        remote_cache_target_hits: ["Excluded"]
      )
    end

    for timestamp <- [reported_at, ~N[2030-01-09 23:59:00], ~N[2030-01-10 12:00:00]] do
      IngestRepo.insert_all(Build, [
        %{
          id: UUIDv7.generate(),
          project_id: 200,
          account_id: 100,
          cacheable_tasks_count: 2,
          tasks_local_hit_count: 0,
          tasks_remote_hit_count: 0,
          tasks_cache_hit_count: 1,
          inserted_at: timestamp
        }
      ])
    end

    # Successful delivery events do not contain the misses needed for a hit rate.
    GradleFixtures.cache_event_fixture(action: "download", inserted_at: reported_at)

    for {client, operation, outcome, timestamp} <- [
          {"bazel", "action_cache", "hit", reported_at},
          {"bazel", "action_cache", "miss", reported_at},
          {"bazel", "action_cache", "miss", reported_at},
          {"bazel", "action_cache", "miss", reported_at},
          {"bazel", "action_cache", "write", reported_at},
          {"bazel", "cas", "hit", reported_at},
          {"xcode", "action_cache", "hit", reported_at},
          {"bazel", "action_cache", "hit", ~N[2030-01-09 23:59:00]},
          {"bazel", "action_cache", "hit", ~N[2030-01-10 12:00:00]}
        ] do
      IngestRepo.insert_all(CacheEvent, [
        %{
          id: UUIDv7.generate(),
          client_kind: client,
          operation: operation,
          outcome: outcome,
          project_id: 200,
          inserted_at: timestamp
        }
      ])
    end

    assert CacheGlobe.snapshot(now).breakdown == %{
             "module" => 30.0,
             "gradle" => 50.0,
             "bazel" => 25.0,
             "all" => 31.25
           }
  end

  test "recorded misses produce zero while unreported caches remain unavailable" do
    IngestRepo.insert_all(Build, [
      %{
        id: UUIDv7.generate(),
        project_id: 200,
        account_id: 100,
        cacheable_tasks_count: 1,
        tasks_local_hit_count: 0,
        tasks_remote_hit_count: 0,
        tasks_cache_hit_count: 0,
        inserted_at: ~N[2031-01-10 11:00:00]
      }
    ])

    assert CacheGlobe.snapshot(~U[2031-01-10 12:00:00Z]).breakdown == %{
             "module" => nil,
             "gradle" => 0.0,
             "bazel" => nil,
             "all" => 0.0
           }
  end

  test "hit-rate query failures preserve delivery totals and enforce a row-read limit" do
    expect(ClickHouseRepo, :query!, fn _query, _params, _opts ->
      %{rows: [["eu-west", 5, 2048, 5, 2048, ~N[2032-01-10 11:59:00]]]}
    end)

    expect(ClickHouseRepo, :query, 3, fn _query, _params, opts ->
      assert opts[:settings][:max_rows_to_read] == 5_000_000
      assert opts[:settings][:read_overflow_mode] == "throw"
      {:error, %Ch.Error{message: "Row read limit exceeded"}}
    end)

    assert capture_log(fn ->
             snapshot = CacheGlobe.snapshot(~U[2032-01-10 12:00:00Z])
             assert snapshot.downloads == 5
             assert snapshot.bytes == 2048
             assert snapshot.status == :available
             assert snapshot.breakdown == CacheGlobe.empty().breakdown
           end) =~ "hit rate unavailable"
  end

  test "a failed source leaves other rates available and the overall rate unknown" do
    stub(ClickHouseRepo, :query, fn query, _params, _opts ->
      if query =~ "reapi_cache_events" do
        {:error, %Ch.Error{message: "Row read limit exceeded"}}
      else
        then(%{rows: [[1, 2]]}, &{:ok, &1})
      end
    end)

    assert capture_log(fn ->
             assert CacheGlobe.snapshot(~U[2033-01-10 12:00:00Z]).breakdown == %{
                      "module" => 50.0,
                      "gradle" => 50.0,
                      "bazel" => nil,
                      "all" => nil
                    }
           end) =~ "Cache globe bazel hit rate unavailable"
  end

  test "inconsistent hit counts cannot inflate individual or overall rates" do
    stub(ClickHouseRepo, :query, fn query, _params, _opts ->
      counts = if query =~ "gradle_builds", do: [5, 2], else: [0, 2]
      {:ok, %{rows: [counts]}}
    end)

    breakdown = CacheGlobe.snapshot(~U[2034-01-10 12:00:00Z]).breakdown
    assert breakdown["gradle"] == 100.0
    assert_in_delta breakdown["all"], 100 / 3, 0.001
  end
end
