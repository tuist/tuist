defmodule Pulse.Traces.TempoTraceDurationsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.PreTraceDurationStorage
  alias Pulse.Traces.{TempoDiscovery, TempoDuration, TempoRootDiscovery}

  @dir "test/fixtures/traces/"
  @key "trace:duration"
  setup do
    {:ok, rows, 0} = Traces.decode_protobuf(File.read!(@dir <> "tempo-trace-durations-input.protobuf"))
    %{rows: rows, cases: Pulse.JSON.decode!(File.read!(@dir <> "tempo-trace-durations-oracle.json"))}
  end

  test "actual upstream integer and filtered-duration dictionaries over complete retained contexts", ctx do
    for {file, hash} <- [
          {"tempo-trace-durations-input.protobuf", "49937e32dd2b5c270b36d6f404dc22a94b5dbbdea7cba6e27671cd9440b5bba9"},
          {"tempo-trace-durations-oracle.json", "18bced978169149a8d6a59df5bd0c72a649f84e28f7efc1f56db8c30c63402fb"},
          {"tempo-trace-duration-format-oracle.json",
           "c95f19eba3e475a8d9dc4a96ce0171ad91df6f348af918afae9da0e7150a15e9"},
          {"produce_tempo_trace_durations.go.txt", "497b35d0c505683af78abde85dbbc6a107c2dd2e23989009c6c8077adfc07806"}
        ],
        do: assert(Base.encode16(:crypto.hash(:sha256, File.read!(@dir <> file)), case: :lower) == hash)

    assert length(ctx.rows) == 560 and length(ctx.cases) == 6

    for c <- ctx.cases do
      assert c["raw"] == c["complete"]
      opts = [discovery_query: c["query"]]
      assert result(TempoRootDiscovery.json(ctx.rows, @key, opts)) == c["complete"]

      for parts <- [[ctx.rows], [Enum.reverse(ctx.rows)], Enum.chunk_every(ctx.rows, 37), [ctx.rows, ctx.rows]] do
        assert result(native(parts, opts)) == c["complete"]
      end
    end
  end

  test "integer-only formatting matches public Go across boundaries and randomized signed-int64 values" do
    cases = Pulse.JSON.decode!(File.read!(@dir <> "tempo-trace-duration-format-oracle.json"))
    assert length(cases) == 1047
    for [ns, expected] <- cases, do: assert(TempoDuration.format(String.to_integer(ns)) == expected)
    assert TempoDuration.format(9_223_372_036_854_775_807) == "2562047h47m16.854775807s"
    assert TempoDuration.format(1000) == <<49, 194, 181, 115>>
  end

  test "parent windows recover full context outside filters without requiring roots", %{rows: [first, second | _]} do
    opts = [discovery_window: {20_000_000_000, 20_000_000_000}, discovery_query: ~s({resource.service.name="worker"})]
    expected = %{"tagValues" => [%{"type" => "duration", "value" => "19.0000001s"}]}
    parts = [[first], [second]]
    assert result(native(parts, opts)) == expected
    assert result(TempoRootDiscovery.segments_json(parts, @key, opts)) == expected
    assert result(native(Enum.reverse(parts), opts)) == expected
    assert TempoRootDiscovery.json([first, second], @key, opts) == {:error, :unsupported_trace_discovery}
    # The retained envelope changes when an early span falls below the floor.
    assert result(native(parts, opts, first.end_timestamp_ns + 1)) == %{
             "tagValues" => [%{"type" => "duration", "value" => "100ns"}]
           }

    assert result(
             TempoRootDiscovery.segments_json(
               parts,
               @key,
               Keyword.put(opts, :discovery_floor, first.end_timestamp_ns + 1)
             )
           ) == %{"tagValues" => [%{"type" => "duration", "value" => "100ns"}]}

    assert result(native(parts, Keyword.delete(opts, :discovery_query))) == %{
             "tagValues" => [%{"type" => "int", "value" => "19000000100"}]
           }

    assert result(native(parts, Keyword.put(opts, :discovery_window, {21_000_000_000, 21_000_000_000}))) == %{
             "tagValues" => []
           }
  end

  test "unknown and corrupt nonmatches fail and old root/string/window callbacks cannot receive duration", %{
    rows: [first, second | _]
  } do
    opts = [discovery_query: ~s({span.absent="no"})]
    legacy = %{first | otlp: nil}
    assert native([[legacy, second]], opts) == {:error, :trace_metadata_unknown}
    assert TempoRootDiscovery.json([legacy, second], @key, opts) == {:error, :trace_metadata_unknown}
    assert native([[File.read!(@dir <> "trace-invalid-version.parquet")]], opts) == :fallback
    assert {:error, _} = TempoRootDiscovery.json([%{first | kind: 999}], @key, opts)
    window = [discovery_window: {20_000_000_000, 20_000_000_000}, discovery_query: ~s({resource.service.name="worker"})]
    assert native([[legacy], [second]], window) == {:error, :trace_metadata_unknown}
    assert :fallback = NIF.tempo_root_discovery_new(0, @key, [], 0, 0)
    {:ok, duration_state} = NIF.tempo_trace_duration_discovery_new(0, [], 0, 0)
    assert :fallback = NIF.tempo_root_discovery_finish(duration_state)
    {:ok, root_state} = NIF.tempo_root_discovery_new(0, "rootName", [], 0, 0)
    assert :fallback = NIF.tempo_trace_duration_discovery_finish(root_state)
    Runtime.put_env(:pulse, Storage, adapter: PreTraceDurationStorage)
    assert :ok = Storage.append(:traces, "durations", [first, second])
    assert {:ok, _} = Storage.tempo_discovery_json("durations", "intrinsic", @key, opts)

    assert Storage.tempo_discovery_json("durations", "intrinsic", @key, window) ==
             {:error, :unsupported_trace_discovery}

    assert TempoDiscovery.filter("intrinsic", @key, "{} with (most_recent=true)") ==
             {:error, :unsupported_trace_discovery}
  end

  @tag timeout: 120_000
  test "work precedes impossible filters and integer/formatted dictionaries never truncate", %{rows: [first | _]} do
    attrs = for i <- 1..1000, do: %{"key" => "k#{i}", "value" => %{"stringValue" => "v"}}

    dense = %{
      first
      | service: nil,
        resource: %{},
        attributes: %{},
        otlp: %{first.otlp | "resource" => attrs, "attributes" => attrs}
    }

    opts = [discovery_query: ~s({span.absent="no"})]
    assert result(native(Enum.chunk_every(List.duplicate(dense, 999), 32), opts)) == %{"tagValues" => []}
    assert native(Enum.chunk_every(List.duplicate(dense, 1000), 32), opts) == {:error, :trace_discovery_work_limit}
    assert TempoRootDiscovery.json(List.duplicate(dense, 1000), @key, opts) == {:error, :trace_discovery_work_limit}
    rows = for n <- 1..5001, do: %{first | trace_id: hex(n), end_timestamp_ns: first.timestamp_ns + n}

    for opts <- [[], [discovery_query: ~s({resource.service.name="gateway"})]] do
      assert {:ok, body} = native([Enum.take(rows, 5000)], opts)
      assert length(Pulse.JSON.decode!(body)["tagValues"]) == 5000
      assert native([rows], opts) == {:error, :query_resource_limit}
      assert TempoRootDiscovery.json(rows, @key, opts) == {:error, :query_resource_limit}
    end
  end

  defp result({:ok, body}), do: Pulse.JSON.decode!(body)
  defp hex(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
  defp blob([source]) when is_binary(source), do: source

  defp blob(rows) do
    {:ok, source, _, _} = S3.encode_segment(:traces, rows)
    source
  end

  defp add(state, rows, :ok) do
    case NIF.tempo_search_add(state, blob(rows)) do
      {:ok, _} -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp native(parts, opts, floor \\ 0) do
    {:ok, predicates} = TempoDiscovery.filter("intrinsic", @key, opts[:discovery_query])
    {start, finish} = opts[:discovery_window] || {0, 0}
    {:ok, state} = NIF.tempo_trace_duration_discovery_new(floor, predicates, start, finish)

    case Enum.reduce_while(parts, :ok, &add(state, &1, &2)) do
      :ok -> NIF.tempo_trace_duration_discovery_finish(state)
      error -> error
    end
  end
end
