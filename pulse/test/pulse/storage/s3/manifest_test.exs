defmodule Pulse.Storage.S3.ManifestTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.TraceSummary

  defp seg(key, min_ts, max_ts, rows \\ 1) do
    Segment.build(key, min_ts, max_ts, rows)
  end

  test "manifest_key/2 encodes tenant and signal into the S3 path" do
    assert Manifest.manifest_key("acme", "logs") == "tenants/acme/v4/signal=logs/manifest.json"
    assert Manifest.manifest_key("acme", "metrics") == "tenants/acme/v4/signal=metrics/manifest.json"
    assert Manifest.manifest_key("acme") == "tenants/acme/v4/signal=logs/manifest.json"
  end

  test "encode/decode round-trips with all fields" do
    manifest = %Manifest{
      version: 1,
      segments: [
        seg("tenants/t/v4/signal=logs/00-10-a.parquet", 5, 10, 4),
        seg("tenants/t/v4/signal=logs/11-20-b.parquet", 11, 20, 8)
      ]
    }

    {:ok, decoded} =
      manifest
      |> Manifest.encode()
      |> IO.iodata_to_binary()
      |> Manifest.decode()

    # Segments come back sorted by max_ts desc regardless of input order.
    assert Enum.map(decoded.segments, & &1.max_ts) == [20, 10]
    assert Enum.map(decoded.segments, & &1.min_ts) == [11, 5]
    assert Enum.map(decoded.segments, & &1.row_count) == [8, 4]
    assert decoded.version == 1
  end

  test "decode enforces sorted invariant even on scrambled input" do
    scrambled = %{
      "v" => 1,
      "s" => [
        %{"k" => "a", "mn" => 5, "mx" => 10, "r" => 1},
        %{"k" => "c", "mn" => 30, "mx" => 40, "r" => 1},
        %{"k" => "b", "mn" => 15, "mx" => 20, "r" => 1}
      ]
    }

    {:ok, decoded} =
      scrambled
      |> JSON.encode!()
      |> Manifest.decode()

    assert Enum.map(decoded.segments, & &1.max_ts) == [40, 20, 10]
  end

  test "decode rejects a payload missing required fields" do
    bad = ~s({"v": 1, "s": [{"k": "a"}]})
    assert {:error, :invalid_segment} = Manifest.decode(bad)
  end

  test "decode rejects a payload that is not JSON" do
    assert {:error, {:decode_failed, _}} = Manifest.decode("not json at all")
  end

  test "merge/2 preserves the sorted invariant and dedupes on key" do
    manifest = %Manifest{
      segments: [
        seg("b", 10, 20, 2),
        seg("a", 0, 5, 1)
      ]
    }

    new = [
      # Supersedes the existing "b" with fresh row_count
      seg("b", 10, 20, 99),
      # Slots between "b" and "a" by max_ts desc
      seg("c", 6, 8, 3)
    ]

    merged = Manifest.merge(manifest, new)

    assert Enum.map(merged.segments, & &1.key) == ["b", "c", "a"]
    assert Enum.map(merged.segments, & &1.max_ts) == [20, 8, 5]
    # b was replaced by the incoming segment (its row_count updated to 99).
    assert Enum.find(merged.segments, &(&1.key == "b")).row_count == 99
  end

  test "merge/2 with an empty batch is identity" do
    manifest = %Manifest{segments: [seg("a", 0, 5, 1)]}
    assert Manifest.merge(manifest, []) == manifest
  end

  test "merge/2 dedups an incoming batch that repeats a key" do
    # The retry-idempotency path: two register_segments calls carrying
    # the same idempotency key produce two segments with an identical
    # S3 key. Both may arrive in the same flush window. If merge lets
    # both through, the manifest ends up with two entries pointing at
    # one S3 object — a later query would fetch that object twice.
    manifest = %Manifest{segments: []}
    dup = seg("same-key", 10, 20, 2)
    merged = Manifest.merge(manifest, [dup, dup])

    assert Enum.map(merged.segments, & &1.key) == ["same-key"]
  end

  test "prune_by_time drops segments outside the requested range" do
    manifest = %Manifest{
      segments: [
        seg("c", 30, 40, 1),
        seg("b", 10, 20, 1),
        seg("a", 0, 5, 1)
      ]
    }

    kept = Manifest.prune_by_time(manifest, 15, 35)
    assert Enum.map(kept, & &1.key) == ["c", "b"]

    kept_open_start = Manifest.prune_by_time(manifest, nil, 12)
    assert Enum.map(kept_open_start, & &1.key) == ["b", "a"]
  end

  test "prune_by_time with nil bounds returns everything" do
    manifest = %Manifest{
      segments: [seg("a", 0, 5), seg("b", 10, 20)]
    }

    assert Manifest.prune_by_time(manifest, nil, nil) == manifest.segments
  end

  test "replacement retirement round-trips and prevents ingest retry resurrection" do
    sources = [seg("a", 0, 5), seg("b", 6, 10)]
    concurrent = seg("c", 11, 12)
    manifest = Manifest.merge(Manifest.new(), sources ++ [concurrent])
    replacement = seg("replacement", 0, 10, 2)
    assert {:ok, updated} = Manifest.replace(manifest, ["a", "b"], replacement, 123)

    assert Map.new(updated.retired, fn {key, retirement} -> {key, retirement.delete_after} end) == %{
             "a" => 123,
             "b" => 123
           }

    assert Enum.map(updated.segments, & &1.key) == ["c", "replacement"]
    retried = Manifest.merge(updated, sources)
    assert retried.segments == updated.segments
    assert retried.retired["a"].revision == 1
    assert retried.retired["b"].revision == 1
    assert {:ok, ^updated} = updated |> Manifest.encode() |> IO.iodata_to_binary() |> Manifest.decode()
    assert {:error, :compaction_conflict} = Manifest.replace(updated, ["a", "b"], replacement, 456)
  end

  test "cached encoding matches a fresh encoding across appends, edits, removals and dictionary changes" do
    log = fn key, ts, services, project ->
      %{
        seg(key, ts, ts + 1)
        | log_services: services,
          log_labels: %{"error_project" => [project], "error_source" => [""]}
      }
    end

    metric = fn key, ts, names, job ->
      %{seg(key, ts, ts + 1) | metric_names: names, metric_labels: %{"job" => [job]}}
    end

    trace = fn key, ts, id ->
      %{seg(key, ts, ts + 1) | trace_summary: TraceSummary.from_values(["svc"], [id])}
    end

    id = fn n -> n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0") end

    m1 =
      Manifest.merge(Manifest.new(), [
        metric.("a", 1, ["up"], "x"),
        metric.("b", 3, ["up"], "x"),
        trace.("t", 5, id.(1)),
        log.("l1", 2, ["api", "web"], ""),
        log.("l2", 4, ["web"], "")
      ])

    # "a" is listed last, so its dictionary IDs shift once "c" introduces a new set ahead of it.
    m2 = Manifest.merge(m1, [metric.("c", 7, ["down"], "y"), log.("l3", 8, ["api", "worker"], "p")])
    m3 = Manifest.merge(m2, [%{metric.("b", 3, ["other"], "z") | row_count: 9}, log.("l1", 2, ["db"], "")])
    {:ok, m4} = Manifest.replace(m3, ["a", "c"], metric.("ac", 1, ["up"], "x"), 99)
    {:ok, m5} = Manifest.replace(m4, ["l1", "l3"], log.("l13", 2, ["api", "db", "worker"], "p"), 99)

    Enum.reduce([m1, m2, m3, m4, m5], %{}, fn manifest, cache ->
      {iodata, cache} = Manifest.encode(manifest, cache)
      cached = IO.iodata_to_binary(iodata)
      fresh = manifest |> Manifest.encode() |> IO.iodata_to_binary()

      # Cached log dictionary IDs persist across calls, so the bytes may
      # differ from a fresh encoding; the decoded manifest may not.
      assert Manifest.decode(cached) == Manifest.decode(fresh)
      assert {:ok, %{segments: segments}} = Manifest.decode(cached)
      assert segments == Enum.map(manifest.segments, &thin/1)

      assert cache |> Map.keys() |> Enum.filter(&is_binary/1) |> Enum.sort() ==
               manifest.segments |> Enum.map(& &1.key) |> Enum.sort()

      cache
    end)
  end

  test "log summaries survive a cached service dictionary that overflows and restarts" do
    # About 40 KiB of distinct names per generation; two generations exceed
    # the 64 KiB dictionary that the cache would otherwise keep extending.
    names = fn generation -> for i <- 1..200, do: "#{generation}-" <> String.duplicate("s", 190) <> "-#{i}" end

    manifest = fn generation ->
      segments =
        generation
        |> names.()
        |> Enum.chunk_every(4)
        |> Enum.with_index(fn services, i ->
          %{seg("#{generation}-#{i}", i, i + 1) | log_services: Enum.sort(services)}
        end)

      Manifest.merge(Manifest.new(), segments)
    end

    Enum.reduce([manifest.("a"), manifest.("b"), manifest.("a")], %{}, fn manifest, cache ->
      {iodata, cache} = Manifest.encode(manifest, cache)
      assert {:ok, decoded} = iodata |> IO.iodata_to_binary() |> Manifest.decode()
      assert decoded.segments == manifest.segments
      cache
    end)
  end

  test "dictionary-encoded log summaries with unknown IDs decode as unknown" do
    body =
      ~s({"v":1,"s":[{"k":"a","mn":1,"mx":3,"si":[0,5],"ei":3},{"k":"b","mn":1,"mx":2,"si":[1],"ei":0}],) <>
        ~s("services":["api","web"],"log_labels":[{"error_source":[""]}]})

    assert {:ok, %{segments: [a, b]}} = Manifest.decode(body)
    assert {a.log_services, a.log_labels} == {nil, nil}
    assert {b.log_services, b.log_labels} == {["web"], %{"error_source" => [""]}}
  end

  defp thin(%{trace_summary: nil} = segment), do: segment
  defp thin(segment), do: %{segment | trace_summary: %{segment.trace_summary | lookup_hashes: nil}}

  test "invalid retirement deadlines fail closed" do
    assert {:error, :invalid_manifest} = Manifest.decode(~s({"v":1,"s":[],"retired":{"a":"soon"}}))
  end
end

defmodule Pulse.Storage.S3.ManifestDetachTest do
  # Decoded manifests are cached and read by heap-capped ingest processes
  # whose caps include shared binaries. Keys must not stay sub-binaries of the
  # manifest body, or each one counts the whole body against the cap.
  use Pulse.Test.Case, async: true

  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment

  test "decoded segment keys do not reference the manifest body" do
    segments =
      for i <- 1..200 do
        key = "tenants/t/v4/signal=traces/date=2026-10-19/hour=10/#{i}-#{i + 1}-#{String.duplicate("a", 40)}.parquet"
        Segment.build(key, i, i + 1, 1)
      end

    body = %Manifest{version: 1, segments: segments} |> Manifest.encode() |> IO.iodata_to_binary()
    {:ok, decoded} = Manifest.decode(body)

    assert Enum.all?(decoded.segments, &(:binary.referenced_byte_size(&1.key) == byte_size(&1.key)))
  end
end
