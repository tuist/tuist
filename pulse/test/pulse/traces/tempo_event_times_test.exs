defmodule Pulse.Traces.TempoEventTimesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.PreEventTimeDiscoveryStorage
  alias Pulse.Traces.TempoDiscovery
  alias Pulse.Traces.TempoSearch

  @dir Path.expand("../../fixtures/traces", __DIR__)
  @key "event:timeSinceStart"
  @worker ~s'{resource.service.name="worker"}'
  @absent ~s'{resource.service.name="absent"}'

  setup do
    for {file, hash} <- [
          {"tempo-event-times-input.protobuf", "64123afc8f82af3d0d65c11c250810e1cc2e0bfc302695f64f8f353eda5c2ab4"},
          {"tempo-event-times-oracle.json", "0df574bf6a30d9bc24b21552f7bc362d36411144f2cf42ec9e4535010b26e49e"},
          {"produce_tempo_event_times.go.txt", "792adcde45bf95d357cf9f61e8c7a858dc3fce658ca30f410a67b2d76544effe"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@dir, file))), case: :lower) == hash
    end

    {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(@dir, "tempo-event-times-input.protobuf")))
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    %{rows: rows, cases: Pulse.JSON.decode!(File.read!(Path.join(@dir, "tempo-event-times-oracle.json")))}
  end

  test "event offsets keep actual unfiltered integer nanoseconds and complete engine-selected filtered parents", ctx do
    assert length(ctx.rows) == 280
    assert length(ctx.cases) == 7
    assert hd(ctx.cases)["raw"] == hd(ctx.cases)["complete"]
    assert Enum.count(ctx.cases, &(&1["raw"] != &1["complete"])) == 5
    sources = [blob(ctx.rows)]
    reversed = [blob(Enum.reverse(ctx.rows))]
    parts = Enum.map(Enum.chunk_every(ctx.rows, 70), &blob/1)

    for c <- ctx.cases do
      assert_result(TempoDiscovery.json(ctx.rows, "intrinsic", @key, discovery_query: c["query"]), c)

      for layout <- [sources, reversed, sources ++ reversed, parts] do
        assert_result(native(layout, c["query"]), c)
      end
    end

    values = hd(ctx.cases)["complete"]["tagValues"]
    assert %{"type" => "int", "value" => "0"} in values
    assert %{"type" => "int", "value" => "-1"} in values
    assert %{"type" => "int", "value" => "9223372036854775806"} in values
    assert %{"type" => "int", "value" => "-9223372036854775807"} in values
    assert {:ok, ~s'{"tagValues":[]}'} = TempoDiscovery.json(ctx.rows, "event", "timeSinceStart", [])
  end

  test "MCP falls back boundedly rather than calling old string or window callbacks", ctx do
    assert :ok = Storage.append(:traces, "event-times", ctx.rows)
    Runtime.put_env(:pulse, Storage, adapter: PreEventTimeDiscoveryStorage)

    for c <- ctx.cases do
      assert {:ok, [%{"text" => json}]} =
               Tools.call("discover_trace_tag_values", %{
                 "tenant" => "event-times",
                 "scope" => "intrinsic",
                 "key" => @key,
                 "query" => c["query"]
               })

      assert_result({:ok, json}, c)
      assert {:ok, legacy} = TempoDiscovery.query("event-times", "intrinsic", @key, 1, "json", c["query"])
      assert Pulse.JSON.decode!(legacy) == %{"tagValues" => Enum.map(c["complete"]["tagValues"], & &1["value"])}
    end

    assert {:error, :unsupported_trace_discovery} =
             TempoDiscovery.query("event-times", "intrinsic", @key, 2, "json", @worker, {1, 1})
  end

  test "time routing concerns parent source envelopes, not event timestamps, and coalescing broadens results", ctx do
    first = with_events(hd(ctx.rows), [%{"name" => "later", "timestamp_ns" => 5000, "attributes" => %{}}])

    second =
      with_events(%{first | timestamp_ns: 1000, end_timestamp_ns: 1010}, [
        %{"name" => "earlier", "timestamp_ns" => 1, "attributes" => %{}}
      ])

    expected = %{"complete" => %{"tagValues" => [%{"type" => "int", "value" => "4999"}]}}
    assert_result(native([blob([first]), blob([second])], @worker, {1, 1}), expected)

    assert_result(
      TempoDiscovery.segments_json([[first], [second]], "intrinsic", @key,
        discovery_query: @worker,
        discovery_window: {1, 1}
      ),
      expected
    )

    both = %{
      "complete" => %{"tagValues" => [%{"type" => "int", "value" => "-999"}, %{"type" => "int", "value" => "4999"}]}
    }

    assert_result(native([blob([first, second])], @worker, {1, 1}), both)

    assert_result(
      TempoDiscovery.segments_json([[first, second]], "intrinsic", @key,
        discovery_query: @worker,
        discovery_window: {1, 1}
      ),
      both
    )
  end

  test "normalized protobuf default time is explicitly stored zero, while no events invent no values", ctx do
    first = hd(ctx.rows)
    default = with_events(first, [%{"name" => "default", "attributes" => %{}, "timestamp_ns" => 0}])
    expected = %{"complete" => %{"tagValues" => [%{"type" => "int", "value" => "-1"}]}}
    assert_result(native([blob([default])], @worker), expected)
    assert_result(TempoDiscovery.json([default], "intrinsic", @key, discovery_query: @worker), expected)
    empty = with_events(first, [])
    assert {:ok, ~s'{"tagValues":[]}'} = native([blob([empty])], @worker)
  end

  test "legacy and invalid event times poison requests even on nonmatching parents", ctx do
    first = hd(ctx.rows)
    legacy = %{first | otlp: nil}
    assert {:error, :trace_metadata_unknown} = native([blob([legacy])], @absent)

    assert {:error, :trace_metadata_unknown} =
             TempoDiscovery.json([legacy], "intrinsic", @key, discovery_query: @absent)

    for time <- [-1, 9_223_372_036_854_775_808, "1", nil, 1.0, 1.0e20, :missing] do
      event =
        if time == :missing,
          do: %{"name" => "bad", "attributes" => %{}},
          else: %{"name" => "bad", "timestamp_ns" => time, "attributes" => %{}}

      bad = with_events(first, [event])
      assert :fallback = native([blob([bad])], @absent)

      assert {:error, {:decode_failed, :invalid_trace_metadata}} =
               TempoDiscovery.json([bad], "intrinsic", @key, discovery_query: @absent)

      assert {:ok, ~s'{"tagValues":[]}'} = native([blob([bad])], @absent, {1000, 1001})
    end
  end

  @tag timeout: 120_000
  test "event owners and attrs spend work before an impossible predicate", ctx do
    base = with_events(hd(ctx.rows), [%{"timestamp_ns" => 1}, %{"timestamp_ns" => 2}])
    pairs = for i <- 1..1000, do: %{"key" => "k#{i}", "value" => %{"stringValue" => "v"}}
    dense = %{base | otlp: %{base.otlp | "events" => [pairs, pairs]}}
    source = blob([dense])
    {:ok, predicates} = TempoDiscovery.filter("intrinsic", @key, @absent)
    {:ok, state} = NIF.tempo_filtered_discovery_new(0, "intrinsic", @key, predicates)
    for _ <- 1..998, do: assert({:ok, 1} = NIF.tempo_discovery_add(state, source))
    assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(state, source)
    assert :fallback = NIF.tempo_discovery_finish(state)

    assert {:error, :trace_discovery_work_limit} =
             TempoDiscovery.json(List.duplicate(dense, 999), "intrinsic", @key, discovery_query: @absent)
  end

  test "5001 distinct signed offsets fail the whole dictionary", ctx do
    base = hd(ctx.rows)
    rows = for i <- 1..5001, do: with_events(base, [%{"timestamp_ns" => 1 + i}])
    assert {:error, :query_resource_limit} = native([blob(rows)], @worker)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(rows, "intrinsic", @key, discovery_query: @worker)
  end

  defp with_events(base, events),
    do: %{base | events: events, otlp: %{base.otlp | "events" => Enum.map(events, fn _ -> [] end)}}

  defp blob(rows) do
    {:ok, source, _, _} = S3.encode_segment(:traces, rows)
    source
  end

  defp native(sources, query, window \\ nil) do
    {:ok, predicates} = TempoDiscovery.filter("intrinsic", @key, query)
    {:ok, state} = new_state(predicates, window)

    result =
      Enum.reduce_while(sources, :ok, fn source, :ok ->
        case NIF.tempo_discovery_add(state, source) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    if result == :ok, do: NIF.tempo_discovery_finish(state), else: result
  end

  defp new_state([], nil), do: NIF.tempo_discovery_new(0, "intrinsic", @key)
  defp new_state(predicates, nil), do: NIF.tempo_filtered_discovery_new(0, "intrinsic", @key, predicates)

  defp new_state(predicates, {start, finish}),
    do: NIF.tempo_windowed_discovery_new(0, "intrinsic", @key, predicates, start, finish)

  defp assert_result({:ok, json}, c), do: assert(Pulse.JSON.decode!(json) == c["complete"], inspect(c))
end
