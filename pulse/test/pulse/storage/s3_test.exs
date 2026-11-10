defmodule Pulse.Storage.S3Test do
  # Round-trips logs through the real S3-compatible endpoint (RustFS via
  # docker-compose). Only runs with PULSE_INTEGRATION=1; plain `mix test`
  # skips it. See test/test_helper.exs.

  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Runtime.Registry
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.ManifestSupervisor

  @moduletag :integration

  setup do
    config = %{
      bucket: System.get_env("PULSE_S3_BUCKET", "pulse"),
      endpoint: System.get_env("PULSE_S3_ENDPOINT", "http://localhost:11100"),
      region: System.get_env("PULSE_S3_REGION", "us-east-1"),
      access_key_id: System.get_env("PULSE_S3_ACCESS_KEY_ID", "rustfsadmin"),
      secret_access_key: System.get_env("PULSE_S3_SECRET_ACCESS_KEY", "rustfsadmin"),
      allow_http: true
    }

    Runtime.put_env(:pulse, S3, config)

    # The application boots ManifestSupervision only when the S3 adapter
    # is configured as the active storage. Tests set the adapter config
    # directly (not through mix env), so we start the tree here.
    start_supervised!(ManifestSupervision)

    tenant = "test-#{System.unique_integer([:positive])}"

    on_exit(
      Runtime.capture(fn ->
        # Delete only the prefix this test owns, with its own metrics instance.
        case ObjectStore.list(config, "tenants/#{tenant}/v4/signal=logs/") do
          {:ok, keys} -> Enum.each(keys, &ObjectStore.delete(config, &1))
          _ -> :ok
        end
      end)
    )

    {:ok, config: config, tenant: tenant}
  end

  defp record(ts, opts \\ []) do
    %Log{
      timestamp_ns: ts,
      severity_text: Keyword.get(opts, :severity_text),
      service: Keyword.get(opts, :service),
      body: Keyword.get(opts, :body),
      attributes: Keyword.get(opts, :attributes, %{}),
      resource: Keyword.get(opts, :resource, %{})
    }
  end

  # The tenant's v3 prefix now also holds the per-tenant `manifest.json`.
  # These helpers narrow object listings to segment files only, so counts
  # remain a proxy for how many *segments* the adapter wrote.
  defp list_segments(config, tenant) do
    with {:ok, keys} <- ObjectStore.list(config, "tenants/#{tenant}/v4/signal=logs/") do
      {:ok, Enum.reject(keys, &String.ends_with?(&1, "/manifest.json"))}
    end
  end

  test "append then query round-trips log records", %{tenant: tenant} do
    assert :ok =
             S3.append(:logs, tenant, [
               record(10, service: "api", body: "hello"),
               record(20, service: "web", body: "world")
             ])

    assert {:ok, records} = S3.query(:logs, tenant, [])
    assert Enum.map(records, & &1.timestamp_ns) == [20, 10]
    assert Enum.map(records, & &1.service) == ["web", "api"]
    assert Enum.map(records, & &1.body) == ["world", "hello"]
  end

  test "records for one tenant are invisible to another", %{tenant: tenant, config: config} do
    other = "test-other-#{System.unique_integer([:positive])}"

    on_exit(
      Runtime.capture(fn ->
        case ObjectStore.list(config, "tenants/#{other}/v4/signal=logs/") do
          {:ok, keys} -> Enum.each(keys, &ObjectStore.delete(config, &1))
          _ -> :ok
        end
      end)
    )

    assert :ok = S3.append(:logs, tenant, [record(1)])
    assert :ok = S3.append(:logs, other, [record(2)])

    assert {:ok, [%Log{timestamp_ns: 1}]} = S3.query(:logs, tenant, [])
    assert {:ok, [%Log{timestamp_ns: 2}]} = S3.query(:logs, other, [])
  end

  test "filters by time range and service", %{tenant: tenant} do
    assert :ok =
             S3.append(:logs, tenant, [
               record(10, service: "api"),
               record(20, service: "web"),
               record(30, service: "api"),
               record(40, service: "api")
             ])

    assert {:ok, records} = S3.query(:logs, tenant, start_ts: 15, end_ts: 35, service: "api")
    assert Enum.map(records, & &1.timestamp_ns) == [30]
  end

  test "applies limit", %{tenant: tenant} do
    assert :ok = S3.append(:logs, tenant, [record(1), record(2), record(3), record(4)])
    assert {:ok, records} = S3.query(:logs, tenant, limit: 2)
    assert length(records) == 2
    assert Enum.map(records, & &1.timestamp_ns) == [4, 3]
  end

  test "stores records verbatim without injecting a wall-clock timestamp", %{tenant: tenant} do
    # Wall-clock backfill would defeat retry idempotency (the second call
    # under the same idempotency key would overwrite the first with a
    # later observed_ts). Records that arrive without timestamps are
    # stored as they came in; queries with time bounds naturally skip
    # them, unbounded queries return them.
    assert :ok =
             S3.append(:logs, tenant, [
               %Log{timestamp_ns: nil, observed_timestamp_ns: nil, body: "no ts"}
             ])

    assert {:ok, [%Log{timestamp_ns: nil, observed_timestamp_ns: nil, body: "no ts"}]} =
             S3.query(:logs, tenant, [])
  end

  test "preserves control-character bodies through the round trip", %{tenant: tenant} do
    tricky = "line1\nline2\t\"quoted\"\r\nline3"
    assert :ok = S3.append(:logs, tenant, [record(1, body: tricky)])
    assert {:ok, [%Log{body: ^tricky}]} = S3.query(:logs, tenant, [])
  end

  test "append with an empty batch is a no-op", %{tenant: tenant, config: config} do
    assert :ok = S3.append(:logs, tenant, [])
    assert {:ok, keys} = list_segments(config, tenant)
    assert keys == []
  end

  test "rejects tenant names that could escape the prefix" do
    for bad <- ["../evil", "foo/bar", "foo bar", "", String.duplicate("a", 200)] do
      assert {:error, {:invalid_tenant, ^bad}} = S3.append(:logs, bad, [record(1)])
      assert {:error, {:invalid_tenant, ^bad}} = S3.query(:logs, bad, [])
    end
  end

  test "same idempotency_key deduplicates identical retries", %{
    tenant: tenant,
    config: config
  } do
    # Opt-in idempotency: a caller that wants retry safety passes the same
    # idempotency_key on the retry. The object key becomes deterministic,
    # so the second PUT overwrites the first with identical content and no
    # duplicate appears at query time.
    batch = [record(1, body: "same", service: "api")]

    assert :ok = S3.append(:logs, tenant, batch, idempotency_key: "req-1")
    assert :ok = S3.append(:logs, tenant, batch, idempotency_key: "req-1")

    assert {:ok, keys} = list_segments(config, tenant)
    assert length(keys) == 1

    assert {:ok, records} = S3.query(:logs, tenant, [])
    assert length(records) == 1
  end

  test "without an idempotency_key identical batches remain distinct writes", %{
    tenant: tenant,
    config: config
  } do
    # If a caller doesn't opt in, two producers with byte-identical payloads
    # must not silently collapse — that would drop data.
    batch = [record(1, body: "same", service: "api")]

    assert :ok = S3.append(:logs, tenant, batch)
    assert :ok = S3.append(:logs, tenant, batch)

    assert {:ok, keys} = list_segments(config, tenant)
    assert length(keys) == 2
  end

  test "a segment still referenced by the manifest cannot silently disappear from query results", %{
    tenant: tenant,
    config: config
  } do
    assert :ok = S3.append(:logs, tenant, [record(1), record(2)])
    assert :ok = S3.append(:logs, tenant, [record(3)])

    # Delete data without retiring its manifest reference. A legitimate
    # compaction or retention job updates metadata before deleting data.
    assert {:ok, [first | _]} = list_segments(config, tenant)
    assert :ok = ObjectStore.delete(config, first)

    # A metadata refresh still references the missing segment, so the query
    # must fail instead of silently returning an incomplete result.
    assert {:error, :not_found} = S3.query(:logs, tenant, [])
  end

  test "equal timestamps sort deterministically across adapters", %{tenant: tenant} do
    a = %Log{timestamp_ns: 10, observed_timestamp_ns: 100, trace_id: "aaa"}
    b = %Log{timestamp_ns: 10, observed_timestamp_ns: 300, trace_id: "aaa"}
    c = %Log{timestamp_ns: 10, observed_timestamp_ns: 200, trace_id: "bbb"}

    assert :ok = S3.append(:logs, tenant, [a, b, c])
    assert {:ok, sorted} = S3.query(:logs, tenant, [])
    assert Enum.map(sorted, & &1.observed_timestamp_ns) == [300, 200, 100]
  end

  describe "manifest coordination" do
    test "append populates the manifest and the ETS cache", %{tenant: tenant} do
      assert :ok = S3.append(:logs, tenant, [record(1, service: "api")])

      entry = ManifestCache.get(tenant, "logs")
      assert %{manifest: %Manifest{segments: [segment | _]}, etag: etag} = entry
      assert is_binary(etag) and etag != ""
      assert segment.min_ts == 1 and segment.max_ts == 1 and segment.row_count == 1
    end

    test "concurrent appends coalesce into a bounded number of CAS operations", %{tenant: tenant} do
      # Fan out N tasks, each with a unique record so no idempotency
      # dedup kicks in. Under coalescing they should all be batched into
      # far fewer than N manifest CAS operations. We assert the
      # loose-but-informative property: every record shows up, all
      # tasks report :ok, and the manifest holds N segments in the end.
      n = 32

      tasks =
        for i <- 1..n do
          Task.async(
            Runtime.capture(fn ->
              S3.append(:logs, tenant, [record(i, service: "svc-#{i}")])
            end)
          )
        end

      results = Task.await_many(tasks, 30_000)
      assert Enum.all?(results, &(&1 == :ok))

      entry = ManifestCache.get(tenant, "logs")
      assert %Manifest{segments: segments} = entry.manifest
      assert length(segments) == n

      # And the query path finds every one of them.
      assert {:ok, records} = S3.query(:logs, tenant, [])
      assert length(records) == n
    end

    test "query rebuilds the manifest from LIST when it has been deleted from S3",
         %{tenant: tenant, config: config} do
      # A tenant whose manifest file gets nuked (retention, operator
      # error, a mid-migration crash) should not lose queryability. On
      # the next query the owner LIST-fallbacks and rebuilds the
      # manifest from the segments that survive in S3.
      assert :ok = S3.append(:logs, tenant, [record(1), record(2)])
      assert :ok = S3.append(:logs, tenant, [record(3)])

      manifest_key = Manifest.manifest_key(tenant)
      assert :ok = ObjectStore.delete(config, manifest_key)
      # Force a cold-start on the next call: drop the cache and stop the
      # per-tenant owner so `ensure_loaded` rebuilds fresh.
      ManifestCache.drop(tenant, "logs")
      stop_owner(tenant)

      assert {:ok, records} = S3.query(:logs, tenant, [])
      assert Enum.map(records, & &1.timestamp_ns) == [3, 2, 1]
    end

    test "rebuild skips non-segment objects (sidecars, junk under the prefix)",
         %{tenant: tenant, config: config} do
      # Codex F2: rebuild used to include every object under the v3
      # prefix, so a sidecar file (or a stray upload) would land in the
      # manifest with nil bounds — and then the next load of that
      # manifest would fail decode. This asserts that non-`.parquet`
      # objects are skipped at rebuild time.
      assert :ok = S3.append(:logs, tenant, [record(1)])

      # Stash a sidecar-shaped object next to the segment.
      sidecar_key = "tenants/#{tenant}/v4/signal=logs/00000000000000000005-junk.bloom"
      assert {:ok, _etag} = ObjectStore.put(config, sidecar_key, "not a segment")

      # And a Parquet-suffixed file with a key that doesn't carry the
      # bounds format — a hypothetical hand-written import.
      malformed_key = "tenants/#{tenant}/v4/signal=logs/hand-written.parquet"
      assert {:ok, _etag} = ObjectStore.put(config, malformed_key, "still not a segment")

      # Force a cold-start rebuild.
      manifest_key = Manifest.manifest_key(tenant)
      assert :ok = ObjectStore.delete(config, manifest_key)
      ManifestCache.drop(tenant, "logs")
      stop_owner(tenant)

      assert {:ok, records} = S3.query(:logs, tenant, [])
      assert Enum.map(records, & &1.timestamp_ns) == [1]

      # Manifest is now on disk and must be reloadable — this is the
      # regression Codex flagged: the previous code produced a manifest
      # with `mn: nil`/`mx: nil` entries that failed Segment.from_wire.
      assert {:ok, _etag, body} = ObjectStore.get_if_none_match(config, manifest_key, nil)
      assert {:ok, decoded} = Manifest.decode(body)
      assert length(decoded.segments) == 1
    end

    test "stale cache refreshes via conditional GET so cross-node writes become visible",
         %{tenant: tenant, config: config} do
      # Codex F1: a node whose local writer is idle can't learn about
      # writes another node commits — the cached manifest is served
      # from ETS without checking S3. The refresh path issues a
      # conditional GET when the entry ages past `refresh_stale_ms`,
      # so a stale cache picks up remote writes within that window.
      short_config = Map.put(config, :refresh_stale_ms, 50)

      # Prime the cache on this node with an empty manifest first.
      assert :ok = S3.append(:logs, tenant, [record(1)])
      before_entry = ManifestCache.get(tenant, "logs")
      assert length(before_entry.manifest.segments) == 1

      # Simulate a "remote" writer: PUT a new manifest bytes-first,
      # then override the CAS-visible content by uploading directly.
      # We do this by writing a new segment object out-of-band and
      # patching the manifest to include it, then CAS-updating the
      # manifest with the current etag.
      remote_key =
        "tenants/#{tenant}/v4/signal=logs/00000000000000000042-00000000000000000042-rand-abcdef0123456789-deadbeefdeadbeef.parquet"

      {:ok, remote_body, 42, 42} =
        S3.encode_segment(:logs, [%Log{timestamp_ns: 42, service: "remote", body: "from-node-b"}])

      assert {:ok, _etag} = ObjectStore.put(short_config, remote_key, remote_body)

      # Now emulate what a peer node's ManifestOwner would do: read
      # current manifest, merge the new segment in, CAS-put.
      manifest_key = Manifest.manifest_key(tenant)
      assert {:ok, current_etag, body} = ObjectStore.get_if_none_match(short_config, manifest_key, nil)
      assert {:ok, current} = Manifest.decode(body)
      remote_seg = Segment.build(remote_key, 42, 42, 1)
      merged = Manifest.merge(current, [remote_seg])
      new_payload = merged |> Manifest.encode() |> IO.iodata_to_binary()
      assert {:ok, _new_etag} = ObjectStore.put_if_match(short_config, manifest_key, new_payload, current_etag)

      # Age the local cache past refresh_stale_ms and query — the
      # refresh path should pick up the remote write.
      # The cache entry's `refreshed_at_mono` is set on write; wait
      # slightly longer than refresh_stale_ms so the next query sees
      # it as stale.
      Process.sleep(120)

      Runtime.put_env(:pulse, S3, short_config)
      assert {:ok, records} = S3.query(:logs, tenant, [])
      Runtime.put_env(:pulse, S3, config)

      timestamps = Enum.map(records, & &1.timestamp_ns) |> Enum.sort()
      assert 42 in timestamps
      assert 1 in timestamps
    end

    test "rejects appends with :owner_overloaded when the mailbox is at the cap",
         %{tenant: tenant, config: config} do
      # Codex F3: the owner mailbox used to be unbounded — a sustained
      # burst would grow memory until callers hit the 15s call timeout
      # and got a raw `exit`. `register_segments` now probes
      # `Process.info(pid, :message_queue_len)` against `max_mailbox`
      # (config-overridable) and returns `{:error, :owner_overloaded}`
      # before entering the mailbox. Passing `max_mailbox: 0` forces
      # every subsequent call to trip the cap deterministically —
      # length is always `>= 0`.
      #
      # We first do a normal append to boot the owner (rebuild path
      # and initial CAS), then flip the ceiling to 0 in the config
      # and verify the next call bounces.
      assert :ok = S3.append(:logs, tenant, [record(1)])

      capped_config = Map.put(config, :max_mailbox, 0)
      Runtime.put_env(:pulse, S3, capped_config)

      try do
        assert {:error, :owner_overloaded} = S3.append(:logs, tenant, [record(2)])
      after
        Runtime.put_env(:pulse, S3, config)
      end

      # And once the cap is lifted, subsequent appends succeed
      # normally — this asserts we haven't corrupted owner state.
      assert :ok = S3.append(:logs, tenant, [record(3)])
    end
  end

  defp stop_owner(tenant) do
    case Registry.lookup(ManifestRegistry, {tenant, "logs"}) do
      [{pid, _}] ->
        ref = Process.monitor(pid)
        DynamicSupervisor.terminate_child(Runtime.name(ManifestSupervisor), pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          1_000 -> :ok
        end

      [] ->
        :ok
    end
  end
end
