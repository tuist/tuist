defmodule Pulse.Traces.TempoFilteredUnscopedTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.PreFilteredUnscopedStorage
  alias Pulse.Traces.TempoDiscovery
  alias Pulse.Traces.TempoSearch

  @dir Path.expand("../../fixtures/traces", __DIR__)
  @worker ~s'{resource.service.name="worker"}'

  setup do
    for {file, hash} <- [
          {"tempo-filtered-unscoped-input.protobuf",
           "346a89d43a4bdd349aa873e1afa418bc13db3ff282a9612df531ee0a5fbd4349"},
          {"tempo-filtered-unscoped-oracle.json", "9b70e78fe1076fc9a16d74483bea1ef0f11b925c873661af7d775a1176d089a3"},
          {"produce_tempo_filtered_unscoped.go.txt", "44d01467815cbbec2e45247edbdc93852f2cd9679c559b25a9930fb5aad40e23"}
        ] do
      assert Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@dir, file))), case: :lower) == hash
    end

    {:ok, rows, 0} = Traces.decode_protobuf(File.read!(Path.join(@dir, "tempo-filtered-unscoped-input.protobuf")))
    cases = Pulse.JSON.decode!(File.read!(Path.join(@dir, "tempo-filtered-unscoped-oracle.json")))
    Runtime.put_env(:pulse, TempoSearch, enabled: true)
    %{rows: rows, cases: cases}
  end

  test "complete three-owner values use actual engine-selected parent IDs, not the upstream ignored-filter dictionary",
       ctx do
    assert length(ctx.cases) == 36
    assert Enum.count(ctx.cases, &(&1["raw"] != &1["complete"])) == 18
    assert Enum.count(ctx.cases, &Map.has_key?(&1, "expected_error")) == 2
    forward = blob(ctx.rows)
    reverse = blob(Enum.reverse(ctx.rows))
    parts = Enum.map(Enum.chunk_every(ctx.rows, 57), &blob/1)

    for c <- ctx.cases do
      assert_result(TempoDiscovery.json(ctx.rows, "none", c["key"], discovery_query: c["query"]), c)

      for sources <- [[forward], [reverse], [forward, reverse], parts] do
        assert_result(native(sources, c), c)
      end
    end
  end

  test "MCP reference fallback fences old unscoped and old window callbacks", ctx do
    assert :ok = Storage.append(:traces, "filtered-none", ctx.rows)
    Runtime.put_env(:pulse, Storage, adapter: PreFilteredUnscopedStorage)

    for c <- ctx.cases do
      result =
        Tools.call("discover_trace_tag_values", %{
          "tenant" => "filtered-none",
          "scope" => "none",
          "key" => c["key"],
          "query" => c["query"]
        })

      assert_tool_result(result, c)
    end

    assert {:error, :unsupported_trace_discovery} =
             TempoDiscovery.query("filtered-none", "none", "mixed", 2, "json", @worker, {1, 1000})

    assert {:ok, json} = TempoDiscovery.query("filtered-none", "none", "mixed", 1, "json", @worker)
    c = Enum.find(ctx.cases, &(&1["key"] == "mixed" and &1["query"] == @worker))
    values = c["complete"]["tagValues"] |> Enum.map(& &1["value"]) |> Enum.uniq() |> Enum.sort()
    assert Pulse.JSON.decode!(json) == %{"tagValues" => values}
  end

  test "windowed native and segment reference retain whole-source routing with filters", ctx do
    sources = Enum.chunk_every(ctx.rows, 57)
    encoded = Enum.map(sources, &blob/1)

    for c <- Enum.reject(ctx.cases, &Map.has_key?(&1, "expected_error")) do
      assert_result(native(encoded, c, {1, 1000}), c)

      assert_result(
        TempoDiscovery.segments_json(sources, "none", c["key"],
          discovery_query: c["query"],
          discovery_window: {1, 1000}
        ),
        c
      )

      assert {:ok, json} = native(encoded, c, {1000, 2000})
      assert Pulse.JSON.decode!(json) == %{"tagValues" => []}
    end
  end

  test "same-key equality shortcuts, unsupported filters and reserved root aliases reject", _ctx do
    for {key, query} <- [
          {"mixed", ~s'{resource.mixed="literal"}'},
          {"mixed", ~s'{span.mixed="literal"}'},
          {"mixed", ~s'{instrumentation.mixed="literal"}'},
          {"mixed", ~s'{span.n=1}'},
          {"mixed", @worker <> " with (most_recent=true)"},
          {"root.name", @worker},
          {"root.service.name", @worker}
        ] do
      assert {:error, :unsupported_trace_discovery} = TempoDiscovery.query("t", "none", key, 2, "json", query)
    end

    assert :fallback = NIF.tempo_filtered_discovery_new(0, "none", "mixed", [{"resource", "mixed", "=", "literal"}])

    assert :fallback =
             NIF.tempo_windowed_discovery_new(0, "none", "mixed", [{"span", "mixed", "=", "literal"}], 1, 1000)
  end

  test "legacy and corrupt nonmatches fail before filters, not as empty suggestions", ctx do
    legacy = %{hd(ctx.rows) | otlp: nil}
    c = %{"key" => "mixed", "query" => ~s'{resource.service.name="absent"}'}

    assert {:error, :trace_metadata_unknown} =
             TempoDiscovery.json([legacy], "none", c["key"], discovery_query: c["query"])

    assert {:error, :trace_metadata_unknown} = native([blob([legacy])], c)
    corrupt = File.read!(Path.join(@dir, "trace-invalid-version.parquet"))
    assert :fallback = native([corrupt], c)
  end

  @tag timeout: 120_000
  test "all three requested owners spend work before an impossible predicate", ctx do
    base = hd(ctx.rows)
    pairs = for i <- 1..1000, do: %{"key" => "k#{i}", "value" => %{"stringValue" => "v"}}
    svc = %{"key" => "service.name", "value" => %{"stringValue" => "worker"}}
    dense = %{base | otlp: %{base.otlp | "resource" => [svc | pairs], "attributes" => pairs, "scope" => pairs}}
    source = blob([dense])
    {:ok, predicates} = TempoDiscovery.filter("none", "absent", ~s'{resource.service.name="absent"}')
    {:ok, state} = NIF.tempo_filtered_discovery_new(0, "none", "absent", predicates)
    for _ <- 1..665, do: assert({:ok, 1} = NIF.tempo_discovery_add(state, source))
    assert {:error, :trace_discovery_work_limit} = NIF.tempo_discovery_add(state, source)
    assert :fallback = NIF.tempo_discovery_finish(state)

    assert {:error, :trace_discovery_work_limit} =
             TempoDiscovery.json(List.duplicate(dense, 666), "none", "absent",
               discovery_query: ~s'{resource.service.name="absent"}'
             )
  end

  test "filtered unscoped dictionaries reject 5001 distinct values without partial success", ctx do
    base = hd(ctx.rows)

    rows =
      for i <- 1..5001,
          do: %{
            base
            | otlp: %{base.otlp | "attributes" => [%{"key" => "unique", "value" => %{"stringValue" => "#{i}"}}]}
          }

    c = %{"key" => "unique", "query" => @worker}
    assert {:error, :query_resource_limit} = native([blob(rows)], c)
    assert {:error, :query_resource_limit} = TempoDiscovery.json(rows, "none", "unique", discovery_query: @worker)
  end

  defp blob(rows) do
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    blob
  end

  defp native(sources, c, window \\ nil) do
    {:ok, predicates} = TempoDiscovery.filter("none", c["key"], c["query"])
    {:ok, state} = new_state(c["key"], predicates, window)

    result =
      Enum.reduce_while(sources, :ok, fn source, :ok ->
        case NIF.tempo_discovery_add(state, source) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    if result == :ok, do: NIF.tempo_discovery_finish(state), else: result
  end

  defp new_state(key, predicates, nil), do: NIF.tempo_filtered_discovery_new(0, "none", key, predicates)

  defp new_state(key, predicates, {start, finish}),
    do: NIF.tempo_windowed_discovery_new(0, "none", key, predicates, start, finish)

  defp assert_result(result, %{"expected_error" => "unsupported_trace_tag_type"}),
    do: assert(result == {:error, :unsupported_trace_tag_type})

  defp assert_result({:ok, json}, c), do: assert(Pulse.JSON.decode!(json) == c["complete"], inspect(c))

  defp assert_tool_result(result, %{"expected_error" => "unsupported_trace_tag_type"}),
    do: assert(result == {:error, :unsupported_trace_tag_type})

  defp assert_tool_result({:ok, [%{"text" => json}]}, c), do: assert_result({:ok, json}, c)
end
