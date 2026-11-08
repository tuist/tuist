defmodule Pulse.Storage.S3.ManifestCacheTest do
  use Pulse.Test.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache

  setup do
    start_supervised!(ManifestCache)
    :ok
  end

  test "late 304 and 200 refreshes cannot regress a newer acknowledged owner publication" do
    old = Manifest.new()
    new = %{old | version: 2}
    assert :ok = ManifestCache.put("tenant", "logs", old, "v1")
    starting = ManifestCache.get("tenant", "logs")
    assert :ok = ManifestCache.put("tenant", "logs", new, "v2")

    # A delayed conditional GET may return either unchanged v1 or another
    # snapshot read before v2 was published. Neither may regress the cache.
    for response_etag <- ["v1", "intermediate"] do
      assert :ok = ManifestCache.put_if_current("tenant", "logs", starting.manifest, response_etag, starting.etag)
      assert %{manifest: ^new, etag: "v2"} = ManifestCache.get("tenant", "logs")
    end

    assert :ok = ManifestCache.put_if_current("tenant", "logs", new, "v3", "v2")
    assert %{etag: "v3"} = ManifestCache.get("tenant", "logs")
  end

  test "publication installs on its base ETag and invalidates incomparable intervening snapshots" do
    old = Manifest.new()
    published = %{old | version: 2}
    ManifestCache.put("tenant", "logs", old, "base")
    base = ManifestCache.publication_base("tenant", "logs")
    assert :ok = ManifestCache.publish("tenant", "logs", published, "published", "base", base)
    assert %{etag: "published"} = ManifestCache.get("tenant", "logs")

    # Either a delayed older publisher or a newer publisher whose cache base
    # was superseded must force a reload; tags themselves cannot decide order.
    assert :ok = ManifestCache.publish("tenant", "logs", old, "delayed", "base", base)
    assert ManifestCache.get("tenant", "logs") == nil
    assert :ok = ManifestCache.publish("tenant", "logs", published, "fresh", "uncached-base", base)
    assert ManifestCache.get("tenant", "logs") == nil
    {nil, token} = ManifestCache.snapshot("tenant", "logs")
    assert :ok = ManifestCache.put_snapshot("tenant", "logs", published, "fresh", token)
    assert %{etag: "fresh"} = ManifestCache.get("tenant", "logs")
  end

  test "stored bytes split by record age, spreading a page reference over its time range" do
    day = 86_400_000_000_000
    now = 400 * day
    seg = fn ts, bytes -> Manifest.Segment.build("k#{ts}", ts - 1, ts, 1, bytes) end
    unsized = %{seg.(now - day, 0) | byte_size: nil}

    flat = %{
      Manifest.new()
      | segments: [seg.(now - 10 * day, 100), seg.(now - 45 * day, 200), seg.(now - 100 * day, 400), unsized]
    }

    assert :ok = ManifestCache.put("tenant", "logs", flat, "v1")

    # A page reference of 600 bytes over the last 60 days: half is younger than 30 days.
    ref = %{"n" => 6, "mn" => now - 60 * day, "mx" => now, "sb" => 600}
    paging = %{"nonce" => String.duplicate("0", 32), "refs" => [ref], "g" => [], "gr" => [], "cc" => 0}
    paged = %{Manifest.new() | version: 4, paging: paging}
    assert :ok = ManifestCache.put("tenant", "traces", paged, "v1")

    assert %{
             "logs" => %{"0-30d" => 100, "30-90d" => 200, "90d+" => 400, unknown: 1},
             "traces" => %{"0-30d" => 300, "30-90d" => 300, "90d+" => 0, unknown: 0}
           } = ManifestCache.stored_bytes(now)
  end

  test "cold publication is fenced by the empty generation observed before CAS" do
    manifest = Manifest.new()
    base = ManifestCache.publication_base("tenant", "logs")
    ManifestCache.publish("tenant", "logs", manifest, "first", nil, base)
    assert %{etag: "first"} = ManifestCache.get("tenant", "logs")
    ManifestCache.drop("tenant", "logs")
    ManifestCache.publish("tenant", "logs", manifest, "delayed-first", nil, base)
    assert ManifestCache.get("tenant", "logs") == nil
    fresh = ManifestCache.publication_base("tenant", "logs")
    ManifestCache.publish("tenant", "logs", manifest, "latest", "first", fresh)
    assert %{etag: "latest"} = ManifestCache.get("tenant", "logs")
  end

  test "invalidation fences delayed publications and reads that began with an absent cache" do
    old = Manifest.new()
    {nil, absent} = ManifestCache.snapshot("tenant", "logs")
    ManifestCache.put("tenant", "logs", old, "X")
    base = ManifestCache.publication_base("tenant", "logs")
    # Z committed after Y, but its predecessor Y was never installed locally.
    ManifestCache.publish("tenant", "logs", old, "Z", "Y", base)
    assert ManifestCache.get("tenant", "logs") == nil
    ManifestCache.publish("tenant", "logs", old, "Y", "X", base)
    ManifestCache.put_snapshot("tenant", "logs", old, "pre-ACK-read", absent)
    assert ManifestCache.get("tenant", "logs") == nil
    {nil, token} = ManifestCache.snapshot("tenant", "logs")
    ManifestCache.put_snapshot("tenant", "logs", old, "fresh-Z", token)
    assert %{etag: "fresh-Z"} = ManifestCache.get("tenant", "logs")
  end

  test "publication generations also fence repeated predecessor ETags" do
    manifest = Manifest.new()

    for initially_warm? <- [false, true] do
      ManifestCache.drop("tenant", "logs")
      if initially_warm?, do: ManifestCache.put("tenant", "logs", manifest, "A")
      base = ManifestCache.publication_base("tenant", "logs")
      ManifestCache.put("tenant", "logs", manifest, "B")
      ManifestCache.put("tenant", "logs", manifest, "A")
      ManifestCache.publish("tenant", "logs", manifest, "delayed-B", "A", base)
      assert ManifestCache.get("tenant", "logs") == nil
    end
  end

  test "cold readers insert only while the cache is still absent" do
    manifest = Manifest.new()
    assert :ok = ManifestCache.put_if_current("tenant", "metrics", manifest, "initial", nil)
    assert :ok = ManifestCache.put("tenant", "metrics", manifest, "published")
    assert :ok = ManifestCache.put_if_current("tenant", "metrics", manifest, "late-initial", nil)
    assert %{etag: "published"} = ManifestCache.get("tenant", "metrics")
  end

  test "eviction drops least recently used roots to the byte bound and fences their generation" do
    manifest = Manifest.new()
    for tenant <- ~w(a b c), do: ManifestCache.put(tenant, "logs", manifest, "e-" <> tenant)
    # Reading `a` makes it the most recently used root.
    assert %{etag: "e-a"} = ManifestCache.get("a", "logs")
    stale_base = ManifestCache.publication_base("b", "logs")
    {_, bytes, _} = ManifestCache.sizes()["logs"] |> then(&{&1, &1[1], nil})
    one = div(bytes, 3)

    assert {2, evicted} = ManifestCache.evict(one)
    assert evicted == 2 * one
    assert %{etag: "e-a"} = ManifestCache.get("a", "logs")
    assert ManifestCache.get("b", "logs") == nil
    assert ManifestCache.get("c", "logs") == nil

    # A publication that started before eviction cannot install over the fence.
    ManifestCache.publish("b", "logs", manifest, "late", "e-b", stale_base)
    assert ManifestCache.get("b", "logs") == nil
    {nil, token} = ManifestCache.snapshot("b", "logs")
    ManifestCache.put_snapshot("b", "logs", manifest, "reloaded", token)
    assert %{etag: "reloaded"} = ManifestCache.get("b", "logs")

    # The most recently used root survives even a zero bound.
    assert {1, _} = ManifestCache.evict(0)
    assert %{etag: "reloaded"} = ManifestCache.get("b", "logs")
  end

  test "pressure eviction drops only roots idle since a cutoff, within the byte bound" do
    manifest = Manifest.new()
    ManifestCache.put("idle", "logs", manifest, "e-idle")
    cutoff = System.monotonic_time(:millisecond) + 1
    # Wait out the cutoff without sleeping on a fixed duration.
    Stream.repeatedly(fn -> System.monotonic_time(:millisecond) end) |> Enum.find(&(&1 > cutoff))
    ManifestCache.put("hot", "logs", manifest, "e-hot")
    ManifestCache.put("hotter", "logs", manifest, "e-hotter")

    assert {0, 0} = ManifestCache.evict(1 <<< 40)
    assert {1, _} = ManifestCache.evict(1 <<< 40, cutoff)
    assert ManifestCache.get("idle", "logs") == nil
    assert %{etag: "e-hot"} = ManifestCache.get("hot", "logs")
    assert %{etag: "e-hotter"} = ManifestCache.get("hotter", "logs")
  end
end
