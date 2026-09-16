defmodule Tuist.Marketing.CacheGlobeTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Marketing.CacheGlobe

  test "counts delivered requests, deduplicates retries, and exposes only public regional totals" do
    event = %{
      event_id: "globe-download",
      account_id: 100,
      project_id: 200,
      node_id: "private-node",
      region: "eu-central",
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
      %{event | event_id: "globe-yesterday", window_start: ~N[2025-01-09 23:59:00]},
      %{event | event_id: "globe-future", window_start: ~N[2025-01-10 12:01:00]},
      %{event | event_id: "globe-upload", operation: "upload", direction: "ingress"},
      %{event | event_id: "globe-peer", traffic_plane: "peer"},
      %{event | event_id: "globe-private", region: "scw-fr-par-runners"},
      %{event | event_id: "globe-unknown", region: "unknown"}
    ])

    snapshot = CacheGlobe.snapshot(~U[2025-01-10 12:00:00Z])

    assert snapshot.downloads == 10
    assert snapshot.bytes == 4096
    assert snapshot.recent_downloads == 5
    assert snapshot.observed_at == "2025-01-10T11:59:00Z"
    assert Enum.find(snapshot.regions, &(&1.id == "eu-central")).downloads == 10
    refute JSON.encode!(snapshot) =~ "private-node"
    refute JSON.encode!(snapshot) =~ "account_id"
    refute JSON.encode!(snapshot) =~ "project_id"
  end

  test "no reports is a waiting state, not a fabricated live counter" do
    snapshot = CacheGlobe.snapshot(~U[2001-01-01 12:00:00Z])
    assert snapshot.status == :waiting
    assert snapshot.downloads == 0
    assert snapshot.observed_at == nil
    assert Enum.all?(snapshot.regions, &(&1.recent_downloads == 0))
  end
end
