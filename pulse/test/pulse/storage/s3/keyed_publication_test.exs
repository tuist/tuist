defmodule Pulse.Storage.S3.KeyedPublicationTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.OTLP.Traces
  alias Pulse.Record.Exemplar
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Record.NativeHistogram
  alias Pulse.RemoteWrite.Push
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricsCompactor
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  setup do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "keyed-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{agent: agent, config: config, tenant: "keyed-#{System.unique_integer([:positive])}"}
  end

  test "all signal retries verify exact immutable bytes without overwriting or duplicating", ctx do
    assert ObjectStore.NIF.keyed_publication_api_version() == 1
    assert :ok = ObjectStore.ensure_retention_api!()

    for signal <- [:logs, :metrics, :traces] do
      rows = rows(signal)
      key = key(ctx, signal, rows)
      assert :ok = S3.append(signal, ctx.tenant, rows, idempotency_key: "key")
      original = object(ctx, key)
      {_, bytes} = original
      ManifestCache.drop(ctx.tenant, Atom.to_string(signal))
      assert :ok = S3.append(signal, ctx.tenant, rows, idempotency_key: "key")
      assert object(ctx, key) == original
      assert count(ctx, "PUT", key) == 2
      assert count(ctx, "GET", key) == 1
      assert {:ok, manifest} = load(ctx, signal)
      assert [%{key: ^key, byte_size: size, row_count: 1}] = manifest.segments
      assert size == byte_size(bytes)
      assert {:ok, [_]} = S3.query(signal, ctx.tenant, [])
    end
  end

  test "a committed create whose error response is not retried is recovered before publication", ctx do
    for signal <- [:logs, :metrics, :traces] do
      rows = rows(signal)
      key = key(ctx, signal, rows)
      Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", key} => {400, :after, 1}}})
      assert :ok = S3.append(signal, ctx.tenant, rows, idempotency_key: "key")
      assert count(ctx, "PUT", key) == 1
      assert count(ctx, "GET", key) == 1
      assert {:ok, %{segments: [%{key: ^key}]}} = load(ctx, signal)
    end
  end

  test "historical rich metric retries retain their hashes, object keys and exact bytes", ctx do
    dir = Path.expand("../../../fixtures/metrics/legacy_1_38", __DIR__)
    hashes = dir |> Path.join("hashes.json") |> File.read!() |> Pulse.JSON.decode!()
    histogram = %NativeHistogram{count: 2.0, sum: 3.0}
    exemplars = [%Exemplar{labels: %{"trace_id" => "abc"}, value: 2.0, timestamp_ns: 1}]

    for {name, hist, ex} <- [
          {"histogram", histogram, nil},
          {"exemplar", nil, exemplars},
          {"both", histogram, exemplars}
        ] do
      rows = [
        %MetricSample{
          timestamp_ns: 1,
          value: if(!hist, do: 2.0),
          labels: %{"__name__" => "work", "host" => "a"},
          histogram: hist,
          exemplars: ex
        }
      ]

      hash = Map.fetch!(hashes, name)
      assert {:ok, ^hash} = S3.caller_content_hash(:metrics, rows)
      bytes = File.read!(Path.join(dir, "keyed_#{name}.parquet"))
      assert {:ok, ^bytes, 1, 1, 1} = NIF.encode_metric_segment_parquet_v2(rows)
      key = S3.object_key(ctx.tenant, "metrics", 1, 1, hash, name)
      assert {:ok, _} = ObjectStore.put(ctx.config, key, bytes)

      # The old writer uploaded, but may have lost its response before CAS.
      assert :ok = S3.append(:metrics, ctx.tenant, rows, idempotency_key: name)
      ManifestCache.drop(ctx.tenant, "metrics")
      assert :ok = S3.append(:metrics, ctx.tenant, rows, idempotency_key: name)
      assert {_, ^bytes} = object(ctx, key)
      assert {:ok, manifest} = load(ctx, :metrics)
      assert Enum.count(manifest.segments, &(&1.key == key)) == 1
    end

    assert {:ok, %{segments: segments}} = load(ctx, :metrics)
    assert length(segments) == 3
  end

  test "different encodings of identical logical metric rows fail closed without replacing bytes", ctx do
    rows = rows(:metrics)
    key = key(ctx, :metrics, rows)
    {:ok, indexed, _, _, _} = NIF.encode_metric_segment_parquet_indexed_v1(rows)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, indexed)
    original = object(ctx, key)
    assert {:error, :keyed_content_mismatch} = S3.append(:metrics, ctx.tenant, rows, idempotency_key: "key")
    assert object(ctx, key) == original
    refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, Manifest.manifest_key(ctx.tenant, "metrics")))
    # fixture seed plus conditional create
    assert count(ctx, "PUT", key) == 2
    assert count(ctx, "GET", key) == 1

    assert Pulse.SelfMetrics.render()
           |> IO.iodata_to_binary()
           |> String.contains?("pulse_keyed_publication_conflicts_total 1\n")
  end

  test "same-sized corrupt content never becomes an acknowledged registration or repair", ctx do
    for signal <- [:logs, :metrics, :traces] do
      rows = rows(signal)
      key = key(ctx, signal, rows)
      bytes = encoded(signal, rows)
      <<first, tail::binary>> = bytes
      corrupt = <<Bitwise.bxor(first, 1), tail::binary>>
      assert {:ok, _} = ObjectStore.put(ctx.config, key, corrupt)
      original = object(ctx, key)
      assert {:error, :keyed_content_mismatch} = S3.append(signal, ctx.tenant, rows, idempotency_key: "key")
      assert object(ctx, key) == original
      refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, Manifest.manifest_key(ctx.tenant, Atom.to_string(signal))))
    end
  end

  test "expired explicit deadlines perform no segment publication or verification I/O", ctx do
    rows = rows(:metrics)

    assert {:error, :timeout} =
             S3.append(:metrics, ctx.tenant, rows,
               idempotency_key: "key",
               deadline_ms: System.monotonic_time(:millisecond) - 1
             )

    requests = Agent.get(ctx.agent, & &1.requests)
    # Retention admission can still read its authoritative managed marker.
    refute Enum.any?(requests, fn {method, key} -> method == "PUT" or String.ends_with?(key, ".parquet") end)
    assert ObjectStore.verify(ctx.config, "missing", "", 0) == {:error, :timeout}
    assert Agent.get(ctx.agent, & &1.requests) == requests
  end

  test "an unavailable verification cannot acknowledge or publish an existing upload", ctx do
    rows = rows(:logs)
    key = key(ctx, :logs, rows)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, encoded(:logs, rows))
    original = object(ctx, key)
    # 403 is not retried by the native client; no busy backoff or sleeps.
    Agent.update(ctx.agent, &%{&1 | faults: %{{"GET", key} => {403, :before, 1}}})
    assert {:error, :keyed_recovery_unavailable} = S3.append(:logs, ctx.tenant, rows, idempotency_key: "key")
    assert object(ctx, key) == original
    refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, Manifest.manifest_key(ctx.tenant, "logs")))
  end

  test "412 then missing GET has at most two create and verification rounds", ctx do
    for missing <- [1, 2] do
      tenant = ctx.tenant <> "-#{missing}"
      ctx = %{ctx | tenant: tenant}
      rows = rows(:metrics)
      key = key(ctx, :metrics, rows)
      assert {:ok, _} = ObjectStore.put(ctx.config, key, encoded(:metrics, rows))
      original = object(ctx, key)
      Agent.update(ctx.agent, &%{&1 | requests: [], faults: %{{"GET", key} => {404, :before, missing}}})
      result = S3.append(:metrics, tenant, rows, idempotency_key: "key")
      assert result == if(missing == 1, do: :ok, else: {:error, :keyed_recovery_unavailable})
      assert object(ctx, key) == original
      assert count(ctx, "PUT", key) == 2
      assert count(ctx, "GET", key) == 2
    end
  end

  test "an independent instance can publish while the successful creator's response is paused", ctx do
    parent = self()
    rows = rows(:metrics)
    key = key(ctx, :metrics, rows)
    Agent.update(ctx.agent, &%{&1 | barriers: %{{"PUT", key} => parent}})
    peer = %{Runtime.current() | instance: __MODULE__.Peer}

    Runtime.with(peer, fn ->
      start_supervised!(Supervisor.child_spec(ManifestSupervision, id: :peer_manifests))
    end)

    tasks = start_supervised!(Task.Supervisor)
    first = Task.Supervisor.async_nolink(tasks, fn -> S3.append(:metrics, ctx.tenant, rows, idempotency_key: "key") end)
    assert_receive {:storage_barrier, writer, "PUT", ^key}, 30_000
    original = object(ctx, key)
    Agent.update(ctx.agent, &%{&1 | barriers: %{}})
    assert :ok = Runtime.with(peer, fn -> S3.append(:metrics, ctx.tenant, rows, idempotency_key: "key") end)
    assert object(ctx, key) == original
    send(writer, {:release_storage, key})
    assert Task.await(first, 5000) == :ok
    assert {:ok, %{segments: [_]}} = load(ctx, :metrics)
    assert count(ctx, "PUT", key) == 2
    assert count(ctx, "GET", key) == 1
  end

  test "restart after proven lost-response publication reuses the same immutable upload", ctx do
    rows = rows(:logs)
    key = key(ctx, :logs, rows)
    manifest_key = Manifest.manifest_key(ctx.tenant, "logs")
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", manifest_key} => {400, :after, 1}}})
    # Fresh root readback proves the CAS committed, so returning an error here
    # would discard evidence that every immutable key is already registered.
    assert :ok = S3.append(:logs, ctx.tenant, rows, idempotency_key: "key")
    original = object(ctx, key)
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert :ok = S3.append(:logs, ctx.tenant, rows, idempotency_key: "key")
    assert object(ctx, key) == original
    assert {:ok, %{segments: [_]}} = load(ctx, :logs)
  end

  test "restart after unproved lost-response publication retains the same immutable upload", ctx do
    rows = rows(:logs)
    key = key(ctx, :logs, rows)
    root = Manifest.manifest_key(ctx.tenant, "logs")
    hook = fn state -> %{state | faults: Map.put(state.faults, {"GET", root}, {400, :before, 1})} end
    Agent.update(ctx.agent, &%{&1 | faults: %{{"PUT", root} => {400, :after, 1}}, hook: hook})
    assert {:error, _} = S3.append(:logs, ctx.tenant, rows, idempotency_key: "key")
    original = object(ctx, key)
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert :ok = S3.append(:logs, ctx.tenant, rows, idempotency_key: "key")
    assert object(ctx, key) == original
    assert {:ok, %{segments: [_]}} = load(ctx, :logs)
  end

  test "a retry after compaction cleanup never re-exposes a retired source", ctx do
    rows = rows(:metrics)
    key = key(ctx, :metrics, rows)
    assert :ok = S3.append(:metrics, ctx.tenant, rows, idempotency_key: "key")
    more = [%{hd(rows) | timestamp_ns: 101, value: 1.0}]
    assert :ok = S3.append(:metrics, ctx.tenant, more, idempotency_key: "other")
    before = S3.query(:metrics, ctx.tenant, [])
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, _} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, key))
    assert :ok = S3.append(:metrics, ctx.tenant, rows, idempotency_key: "key")
    assert {:ok, manifest} = load(ctx, :metrics)
    assert [%{key: active}] = manifest.segments
    refute active == key
    assert Map.has_key?(manifest.retired, key)
    assert S3.query(:metrics, ctx.tenant, []) == before
    assert {:ok, _} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    refute Agent.get(ctx.agent, &Map.has_key?(&1.objects, key))
    assert S3.query(:metrics, ctx.tenant, []) == before
  end

  test "source starts survive independent instances, restart, exact keyed replay and compaction", ctx do
    fixtures = Path.expand("../../../fixtures/metrics/remote_write_start", __DIR__)
    cases = File.read!(Path.join(fixtures, "prometheus-3.8.0.json")) |> JSON.decode!()

    records =
      for c <- [Enum.at(cases, 1), Enum.at(cases, 8)], reduce: [] do
        rows ->
          assert {:ok, decoded, 0, []} = Push.decode_with_metadata(Base.decode64!(c["snappy_base64"]), 16_777_216, :v2)
          rows ++ decoded
      end

    peer = %{Runtime.current() | instance: __MODULE__.StartPeer}

    Runtime.with(peer, fn ->
      start_supervised!(Supervisor.child_spec(ManifestSupervision, id: :start_peer_manifests))
    end)

    assert :ok = S3.append(:metrics, ctx.tenant, records, idempotency_key: "key")
    original_key = key(ctx, :metrics, records)
    original = object(ctx, original_key)
    assert :ok = Runtime.with(peer, fn -> S3.append(:metrics, ctx.tenant, records, idempotency_key: "key") end)
    assert object(ctx, original_key) == original
    assert {:ok, before} = Runtime.with(peer, fn -> S3.query(:metrics, ctx.tenant, []) end)
    assert Enum.sort(before) == Enum.sort(records)

    # Add legacy rows to exercise nulls in a mixed compacted segment.
    [%MetricSample{} = first | _] = records

    assert :ok =
             S3.append(
               :metrics,
               ctx.tenant,
               [%{first | timestamp_ns: first.timestamp_ns + 1, start_timestamp_ms: nil}],
               idempotency_key: "plain"
             )

    assert {:ok, expected} = S3.query(:metrics, ctx.tenant, [])
    assert :ok = stop_supervised(ManifestSupervision)
    start_supervised!(ManifestSupervision)
    assert :ok = S3.append(:metrics, ctx.tenant, records, idempotency_key: "key")
    assert {:ok, %{merged: 2}} = MetricsCompactor.compact(ctx.tenant, ctx.config, grace_ms: 0)
    assert {:ok, _} = MetricsCompactor.cleanup(ctx.tenant, ctx.config)
    assert :ok = Runtime.with(peer, fn -> S3.append(:metrics, ctx.tenant, records, idempotency_key: "key") end)
    assert S3.query(:metrics, ctx.tenant, []) == {:ok, expected}
    assert Runtime.with(peer, fn -> S3.query(:metrics, ctx.tenant, []) end) == {:ok, expected}
    assert {:ok, %{segments: [_]}} = load(ctx, :metrics)
  end

  defp rows(:logs), do: [%Log{timestamp_ns: 100, service: "api", body: "zero\0µ"}]

  defp rows(:metrics),
    do: [%MetricSample{timestamp_ns: 100, value: -0.0, labels: %{"__name__" => "work", "host" => "a"}}]

  defp rows(:traces) do
    {:ok, rows, 0} = Traces.decode(Fixture.payload([Fixture.span(10)]))
    rows
  end

  defp key(ctx, signal, rows) do
    bytes = encoded(signal, rows)
    {:ok, hash} = S3.caller_content_hash(signal, rows)
    {:ok, decoded} = S3.decode_segment(signal, bytes, nil, nil, [])
    times = Enum.map(decoded, & &1.timestamp_ns)
    S3.object_key(ctx.tenant, Atom.to_string(signal), Enum.min(times), Enum.max(times), hash, "key")
  end

  defp encoded(:metrics, rows) do
    {:ok, bytes, _, _, _} = NIF.encode_metric_segment_parquet_v2(rows)
    bytes
  end

  defp encoded(signal, rows) do
    {:ok, bytes, _, _} = S3.encode_segment(signal, rows)
    bytes
  end

  defp object(ctx, key), do: Agent.get(ctx.agent, &Map.fetch!(&1.objects, key))

  defp count(ctx, method, key),
    do: Agent.get(ctx.agent, &Enum.count(&1.requests, fn request -> request == {method, key} end))

  defp load(ctx, signal) do
    {:ok, bytes} = ObjectStore.get(ctx.config, Manifest.manifest_key(ctx.tenant, Atom.to_string(signal)))
    Manifest.decode(bytes)
  end
end
