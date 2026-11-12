defmodule Pulse.Storage.S3.MetricFooterTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.ObjectStore
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.MetricFooterReader
  alias Pulse.Test.CompactionStore

  setup do
    Runtime.share()

    store =
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

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "footer-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0,
      metric_footer_pruning_enabled: true
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    %{store: store, config: config, tenant: "footer-#{System.unique_integer([:positive])}"}
  end

  test "impossible conjunction skips a full data GET but still charges logical bytes and actual footer rows", ctx do
    records = samples()
    assert :ok = S3.append(:metrics, ctx.tenant, records)
    {key, {tag, body}} = segment(ctx.store)
    size = byte_size(body)
    assert size > 65_536
    # Each value exists in the manifest summary, but no stored series has both.
    matchers = [{"host", :eq, "b"}, {"env", :eq, "prod"}]
    assert {:ok, []} = S3.query(:metrics, ctx.tenant, matchers: matchers)
    assert [{^key, "bytes=-65536", nil}] = Agent.get(ctx.store, & &1.range_requests)
    tail = binary_part(body, size - 65_536, 65_536)
    assert {:ok, 24_576, true} = NIF.metric_segment_footer_plan(tail, size, nil, nil, matchers)

    assert {:ok, %MetricFooterReader{body: nil, rows: 24_576, charge: charge}} =
             MetricFooterReader.read(ctx.config, key, nil, nil, matchers, [])

    assert charge == size

    assert {:error, :query_scan_limit} =
             MetricFooterReader.read(ctx.config, key, nil, nil, matchers, max_scan_bytes: size - 1)

    assert {:error, :query_scan_limit} =
             MetricFooterReader.read(ctx.config, key, nil, nil, matchers, max_scan_rows: 24_575)

    assert {:ok, ^tag, ^size, ^tail} = ObjectStore.get_snapshot(ctx.config, key, nil, 65_536, size, 15_000)
  end

  test "possible matches and unknown/damaged postings use one matching full snapshot and preserve exact samples", ctx do
    records = samples()
    assert :ok = S3.append(:metrics, ctx.tenant, records)
    {key, {tag, original}} = segment(ctx.store)

    for body <- [
          original,
          :binary.replace(original, "pulse.metric.postings.v1", "pulse.metric.postings.v0", [:global]),
          :binary.replace(original, "50554c53454d5031", "50554c53454d5030", [:global])
        ] do
      Agent.update(ctx.store, &%{&1 | objects: Map.put(&1.objects, key, {tag, body})})

      for matchers <- [
            [{"host", :eq, "a"}],
            [{"host", :eq, "a"}, {"host", :eq, "b"}],
            [{"host", :re, "a|b"}],
            [{"host", :neq, "a"}],
            [{"missing", :eq, ""}]
          ] do
        assert {:ok, expected} = NIF.decode_metric_segment_parquet_v2(body, 100, 23_000, matchers)
        assert {:ok, actual} = S3.query(:metrics, ctx.tenant, start_ts: 100, end_ts: 23_000, matchers: matchers)
        assert Enum.sort_by(actual, & &1.timestamp_ns) == Enum.sort_by(expected, & &1.timestamp_ns)
      end
    end

    assert Enum.any?(Agent.get(ctx.store, & &1.range_requests), fn
             {^key, nil, ^tag} -> true
             _ -> false
           end)
  end

  test "snapshot change never mixes old footer with a new body", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, samples())
    {key, {_tag, body}} = segment(ctx.store)
    owner = self()
    Agent.update(ctx.store, &put_in(&1.barriers[{"GET", key}], owner))
    task = Pulse.Runtime.Task.async(fn -> MetricFooterReader.read(ctx.config, key, nil, nil, [], []) end)
    assert_receive {:storage_barrier, server, "GET", ^key}, 30_000

    Agent.update(ctx.store, fn state ->
      %{state | barriers: %{}, objects: Map.put(state.objects, key, {"\"changed\"", body})}
    end)

    send(server, {:release_storage, key})
    assert {:error, :precondition_failed} = Task.await(task, 10_000)
  end

  test "missing after a probe preserves spent cost, expired deadlines do no I/O, and small snapshots are reused", ctx do
    assert :ok = S3.append(:metrics, ctx.tenant, samples())
    {key, {_tag, body}} = segment(ctx.store)
    before = Agent.get(ctx.store, & &1.requests)

    assert {:error, :query_timeout} =
             MetricFooterReader.read(ctx.config, key, nil, nil, [],
               deadline_ms: System.monotonic_time(:millisecond) - 1
             )

    assert Agent.get(ctx.store, & &1.requests) == before
    owner = self()
    Agent.update(ctx.store, &put_in(&1.barriers[{"GET", key}], owner))
    task = Pulse.Runtime.Task.async(fn -> MetricFooterReader.read(ctx.config, key, nil, nil, [], []) end)
    assert_receive {:storage_barrier, server, "GET", ^key}, 30_000
    Agent.update(ctx.store, fn state -> %{state | barriers: %{}, objects: Map.delete(state.objects, key)} end)
    send(server, {:release_storage, key})
    assert {:error, {:footer_source_missing, cost, 24_576}} = Task.await(task, 10_000)
    assert cost == byte_size(body) + 65_536

    assert {:ok, small, _, _, 2} = NIF.encode_metric_segment_parquet_v2(Enum.take(samples(), 2))
    assert {:ok, _} = ObjectStore.put(ctx.config, key, small)
    Agent.update(ctx.store, &Map.put(&1, :range_requests, []))

    assert {:ok, %MetricFooterReader{body: ^small, rows: 2}} =
             MetricFooterReader.read(ctx.config, key, nil, nil, [], [])

    assert [{^key, "bytes=-65536", nil}] = Agent.get(ctx.store, & &1.range_requests)

    assert {:ok, %MetricFooterReader{charge: charge}} =
             MetricFooterReader.read(ctx.config, key, nil, nil, [], max_scan_bytes: byte_size(small))

    assert charge == byte_size(small)
  end

  test "large footers expand once, oversized or damaged footers fall back or reject rather than fabricate empty results",
       ctx do
    body = File.read!(Path.expand("../../../fixtures/metrics/large_footer.parquet", __DIR__))
    key = "tenants/#{ctx.tenant}/large.parquet"
    assert {:ok, tag} = ObjectStore.put(ctx.config, key, body)
    size = byte_size(body)
    tail = binary_part(body, size - 65_536, 65_536)
    assert {:ok, :more, required} = NIF.metric_segment_footer_plan(tail, size, 3, 4, [])
    assert required > 65_536

    assert {:ok, %MetricFooterReader{body: nil, rows: 2, charge: charge}} =
             MetricFooterReader.read(ctx.config, key, 3, 4, [], [])

    assert charge == max(size, 65_536 + required)
    assert [{^key, expanded_range, ^tag}, {^key, "bytes=-65536", nil}] = Agent.get(ctx.store, & &1.range_requests)
    assert expanded_range == "bytes=-#{required}"

    oversized = oversized_footer(body)
    assert {:ok, _} = ObjectStore.put(ctx.config, key, oversized)
    Agent.update(ctx.store, &Map.put(&1, :range_requests, []))

    assert {:ok, %MetricFooterReader{body: ^oversized, rows: 2}} =
             MetricFooterReader.read(ctx.config, key, nil, nil, [], [])

    assert [{^key, nil, _}, {^key, "bytes=-65536", nil}] = Agent.get(ctx.store, & &1.range_requests)

    damaged = binary_part(body, 0, size - 4) <> "NOPE"
    assert {:ok, _} = ObjectStore.put(ctx.config, key, damaged)

    assert {:error, {:decode_failed, :parquet_decoder_rejected_input}} =
             MetricFooterReader.read(ctx.config, key, 3, 4, [], [])
  end

  test "native snapshot bounds and weak tags fail without an unconditioned fallback", ctx do
    key = "tenants/#{ctx.tenant}/bounded.parquet"
    assert {:ok, body, _, _, 2} = NIF.encode_metric_segment_parquet_v2(Enum.take(samples(), 2))
    assert {:ok, _} = ObjectStore.put(ctx.config, key, body)

    assert {:error, :response_too_large} =
             ObjectStore.get_snapshot(ctx.config, key, nil, 65_536, byte_size(body) - 1, 15_000)

    Agent.update(ctx.store, &%{&1 | objects: Map.put(&1.objects, key, {"W/\"weak\"", body})})
    assert {:error, _} = MetricFooterReader.read(ctx.config, key, nil, nil, [], [])
    assert [{^key, "bytes=-65536", nil}, {^key, "bytes=-65536", nil}] = Agent.get(ctx.store, & &1.range_requests)
    before = Agent.get(ctx.store, & &1.requests)
    assert {:error, _} = ObjectStore.get_snapshot(ctx.config, key, nil, 1_048_577, 128_000_000, 15_000)
    assert Agent.get(ctx.store, & &1.requests) == before
  end

  test "feature disabled leaves the ordinary single-body GET path unchanged", ctx do
    Runtime.put_env(:pulse, S3, Map.delete(ctx.config, :metric_footer_pruning_enabled))
    assert :ok = S3.append(:metrics, ctx.tenant, Enum.take(samples(), 2))
    assert {:ok, [_, _]} = S3.query(:metrics, ctx.tenant, [])
    assert Agent.get(ctx.store, &Map.get(&1, :range_requests, [])) == []
  end

  # Expand only the fixture's unknown padding string in Thrift compact metadata.
  # Both lengths fit three varint bytes; no data pages or schema fields change.
  defp oversized_footer(body) do
    {offset, 70_000} = :binary.match(body, :binary.copy("p", 70_000))
    assert binary_part(body, offset - 3, 3) == <<0xF0, 0xA2, 4>>
    size = byte_size(body)
    <<footer_size::little-32>> = binary_part(body, size - 8, 4)
    new_size = 1_048_577

    binary_part(body, 0, offset - 3) <>
      <<0x81, 0x80, 0x40>> <>
      :binary.copy("p", new_size) <>
      binary_part(body, offset + 70_000, size - 8 - offset - 70_000) <>
      <<footer_size + new_size - 70_000::little-32>> <> "PAR1"
  end

  defp segment(store) do
    Agent.get(store, fn state -> Enum.find(state.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end) end)
  end

  defp samples do
    for n <- 1..24_576 do
      %MetricSample{
        timestamp_ns: n,
        value: :erlang.phash2({n, :footer_values}) / 1,
        labels: %{
          "__name__" => "requests",
          "host" => if(rem(n, 2) == 0, do: "a", else: "b"),
          "env" => if(rem(n, 2) == 0, do: "prod", else: "dev")
        }
      }
    end
  end
end
