defmodule Pulse.Traces.TempoSearchTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage.S3
  alias Pulse.Traces.TempoSearch

  defp fixture do
    wire = File.read!(Path.expand("../../fixtures/traces/tempo-search-input.protobuf", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, wire), case: :lower) ==
             "6b7c1a4ebee57c4bd40986e1ffa0505ff1995842a5af1e4e737f0d13b0cf8632"

    assert {:ok, spans, 0} = Traces.decode_protobuf(wire)
    cases = File.read!(Path.expand("../../fixtures/traces/tempo-search-oracle.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, cases), case: :lower) ==
             "611df661e5137363242cd987cfd4f8c18811b85553a75c531f1e727d13e92a65"

    # Upstream equal-start tie order is unspecified. Pulse adds ID ascending
    # determinism; preserve every row while normalizing only that tie order.
    cases = Enum.map(Pulse.JSON.decode!(cases), &update_in(&1["response"], fn response -> normalize(response) end))
    {spans, cases}
  end

  defp normalize(%{"traces" => _} = response),
    do: Map.update!(response, "traces", &Enum.sort_by(&1, fn row -> trace_order(row) end))

  defp normalize(response), do: response
  defp trace_order(row), do: {-String.to_integer(row["startTimeUnixNano"]), String.pad_leading(row["traceID"], 32, "0")}

  test "opt-in gate and MCP trace-wide search do not change window-local search" do
    {spans, [c | _]} = fixture()
    assert :ok = Pulse.Storage.append(:traces, "example", spans)
    opts = [trace_start: 30_000_000_000, trace_end: 40_000_000_000, limit: 100, spss: 3]
    assert {:error, :tempo_search_disabled} = TempoSearch.query("example", c["query"], opts)
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert {:ok, json} = TempoSearch.query("example", c["query"], opts)
    assert Pulse.JSON.decode!(json) == c["response"]

    args = %{
      "tenant" => "example",
      "query" => c["query"],
      "start_ts_ns" => opts[:trace_start],
      "end_ts_ns" => opts[:trace_end]
    }

    assert {:ok, [%{"text" => json}]} = Tools.call("search_trace_metadata", args)
    assert Pulse.JSON.decode!(json) == c["response"]
    assert {:error, _} = Tools.call("search_trace_metadata", %{args | "start_ts_ns" => 0})

    assert {:error, {:invalid_arguments, "start_ts_ns must not exceed end_ts_ns"}} =
             Tools.call("search_trace_metadata", %{args | "start_ts_ns" => 50_000_000_000})
  end

  test "actual public Tempo v2.9.0 Parquet block + TraceQL engine establishes overlap, trace-wide roots/duration and most-recent ordering" do
    {spans, cases} = fixture()
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, spans)

    frames = File.read!(Path.expand("../../fixtures/traces/search-frames.json", __DIR__))

    assert Base.encode16(:crypto.hash(:sha256, frames), case: :lower) ==
             "d297872bcd86e5cf9e6a93ca12396465e2f0d453922f295ad5ec0d4f606ea047"

    frames = Pulse.JSON.decode!(frames)

    for c <- cases do
      assert {:ok, predicates} = TempoSearch.parse(c["query"])

      opts = [
        trace_start: c["Start"] * 1_000_000_000,
        trace_end: c["End"] * 1_000_000_000,
        limit: c["Limit"],
        spss: c["SPSS"]
      ]

      assert {:ok, state} =
               NIF.tempo_search_new(0, opts[:trace_start], opts[:trace_end], predicates, opts[:limit], opts[:spss])

      assert {:ok, 14} = NIF.tempo_search_add(state, blob)
      assert {:ok, actual} = NIF.tempo_search_finish(state)
      actual = Pulse.JSON.decode!(actual)
      assert actual == c["response"], c["name"]
      frame = hd(frames[c["name"]])
      assert frame["schema"]["meta"]["preferredVisualisationType"] == "table"
      assert hd(frame["data"]["values"]) == Enum.map(actual["traces"], & &1["traceID"]), c["name"]
      assert {:ok, reference} = TempoSearch.json(spans, predicates, opts)
      assert Pulse.JSON.decode!(reference) == c["response"], c["name"]
      assert :fallback = NIF.tempo_search_finish(state)
    end
  end

  defp native(rows, predicates, opts) do
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    {:ok, state} = NIF.tempo_search_new(0, opts[:trace_start], opts[:trace_end], predicates, opts[:limit], opts[:spss])
    assert {:ok, _} = NIF.tempo_search_add(state, blob)
    NIF.tempo_search_finish(state)
  end

  test "zero-time nonmatches cannot poison valid results; matched unknown time, ambiguous roots and unrepresentable durations fail explicitly" do
    {spans, [c | _]} = fixture()
    {:ok, predicates} = TempoSearch.parse(c["query"])
    opts = [trace_start: 30_000_000_000, trace_end: 40_000_000_000, limit: 100, spss: 3]
    root = Enum.find(spans, &(&1.name == "newer"))
    matching = Enum.find(spans, &(&1.name == "inside"))
    zero = %{root | trace_id: String.pad_leading("9", 32, "0"), timestamp_ns: 0, end_timestamp_ns: 50_000_000_000}
    assert {:ok, _} = TempoSearch.json([zero | spans], predicates, opts)
    assert {:ok, _} = native([zero | spans], predicates, opts)
    unknown_time = %{matching | trace_id: zero.trace_id, timestamp_ns: 0, end_timestamp_ns: 50_000_000_000}
    conflict = %{root | name: "another-root"}
    duration = %{matching | end_timestamp_ns: 4_294_967_296_000_000 + root.timestamp_ns}

    for {rows, reason} <- [
          {[unknown_time | spans], :trace_timestamp_unknown},
          {[conflict | spans], :trace_root_conflict},
          {[duration | spans], :trace_duration_limit},
          {[conflict, unknown_time | spans], :trace_timestamp_unknown}
        ] do
      assert {:error, ^reason} = TempoSearch.json(rows, predicates, opts)
      assert {:error, ^reason} = native(rows, predicates, opts)
    end
  end

  test "candidate-first search does not spend trace-group capacity on 65537 proven nonmatches and recovers earlier context" do
    {rows, cases} = fixture()
    c = Enum.find(cases, &(&1["name"] == "most-recent-before-limit"))
    {:ok, predicates} = TempoSearch.parse(c["query"])
    root = Enum.find(rows, &(&1.name == "newer"))
    match = Enum.find(rows, &(&1.name == "inside"))
    {:ok, state} = NIF.tempo_search_new(0, 30_000_000_000, 40_000_000_000, predicates, 100, 3)
    {:ok, blob, _, _} = S3.encode_segment(:traces, [root])
    assert {:ok, 1} = NIF.tempo_search_add(state, blob)

    for chunk <- Enum.chunk_every(100..65_636, 1000) do
      spans =
        Enum.map(
          chunk,
          &%{root | trace_id: &1 |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")}
        )

      {:ok, blob, _, _} = S3.encode_segment(:traces, spans)
      assert {:ok, _} = NIF.tempo_search_add(state, blob)
    end

    {:ok, blob, _, _} = S3.encode_segment(:traces, [match])
    assert {:ok, 1} = NIF.tempo_search_add(state, blob)
    assert {:ok, json} = NIF.tempo_search_finish(state)
    assert Pulse.JSON.decode!(json) == c["response"]
    assert :fallback = NIF.tempo_search_finish(state)
  end

  test "captured immutable inputs have a separate 32MiB cap even when no trace matches" do
    {rows, _} = fixture()
    {:ok, predicates} = TempoSearch.parse(~s'{resource.service.name="absent"} with (most_recent=true)')
    row = %{hd(rows) | name: Base.encode64(:crypto.strong_rand_bytes(131_072))}
    {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
    {:ok, state} = NIF.tempo_search_new(0, 30_000_000_000, 40_000_000_000, predicates, 100, 3)
    accepted = div(33_554_432, byte_size(blob))
    assert accepted < 1024
    for _ <- 1..accepted, do: assert({:ok, _} = NIF.tempo_search_add(state, blob))
    assert {:error, :query_resource_limit} = NIF.tempo_search_add(state, blob)
    assert :fallback = NIF.tempo_search_finish(state)
  end

  test "retained input owner bookkeeping is bounded independently of input bytes" do
    {rows, _} = fixture()
    {:ok, predicates} = TempoSearch.parse(~s'{resource.service.name="absent"} with (most_recent=true)')
    {:ok, blob, _, _} = S3.encode_segment(:traces, [hd(rows)])
    {:ok, state} = NIF.tempo_search_new(0, 30_000_000_000, 40_000_000_000, predicates, 100, 3)
    assert byte_size(blob) * 1024 < 33_554_432
    for _ <- 1..1024, do: assert({:ok, _} = NIF.tempo_search_add(state, blob))
    assert {:error, :query_resource_limit} = NIF.tempo_search_add(state, blob)
    assert :fallback = NIF.tempo_search_finish(state)
  end

  test "abort synchronously invalidates retained input state before retry" do
    {rows, cases} = fixture()
    {:ok, predicates} = TempoSearch.parse(hd(cases)["query"])
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    {:ok, state} = NIF.tempo_search_new(0, 30_000_000_000, 40_000_000_000, predicates, 100, 3)
    assert {:ok, _} = NIF.tempo_search_add(state, blob)
    assert :ok = NIF.tempo_search_abort(state)
    assert :fallback = NIF.tempo_search_add(state, blob)
    assert :fallback = NIF.tempo_search_finish(state)
    assert :ok = NIF.tempo_search_abort(state)
  end

  test "partition/order-independent context with duplicate rows; legacy uncertainty is deferred until full-trace overlap" do
    {spans, [c | _]} = fixture()
    {:ok, predicates} = TempoSearch.parse(c["query"])
    opts = [trace_start: 30_000_000_000, trace_end: 40_000_000_000, limit: 100, spss: 3]

    for rows <- [spans, Enum.reverse(spans), Enum.sort_by(spans, &:erlang.phash2/1)] do
      {:ok, state} = NIF.tempo_search_new(0, opts[:trace_start], opts[:trace_end], predicates, 100, 3)

      for chunk <- Enum.chunk_every(rows, 3) do
        {:ok, blob, _, _} = S3.encode_segment(:traces, chunk)
        assert {:ok, _} = NIF.tempo_search_add(state, blob)
      end

      assert {:ok, json} = NIF.tempo_search_finish(state)
      assert Pulse.JSON.decode!(json) == c["response"]
    end

    [legacy | _] = Enum.filter(spans, &(&1.timestamp_ns == 20_000_000_000))
    rows = Enum.map(spans, &if(&1 == legacy, do: %{&1 | otlp: nil}, else: &1))
    assert {:ok, _} = TempoSearch.json(rows, predicates, opts)
    [overlap | _] = Enum.filter(spans, &(&1.timestamp_ns == 32_000_000_000))
    rows = [%{overlap | otlp: nil} | spans]
    assert {:error, :trace_metadata_unknown} = TempoSearch.json(rows, predicates, opts)
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, rows)
    {:ok, state} = NIF.tempo_search_new(0, opts[:trace_start], opts[:trace_end], predicates, 100, 3)
    assert {:ok, _} = NIF.tempo_search_add(state, blob)
    assert {:error, :trace_metadata_unknown} = NIF.tempo_search_finish(state)
    # The most-recent hint is optional: results are always the most recent traces.
    assert {:ok, [{"resource", "service.name", "=", "worker"}]} =
             TempoSearch.parse(~s'{resource.service.name="worker"}')

    assert {:error, {:decode_failed, :invalid_trace_metadata}} =
             TempoSearch.json(spans, [{"resource", "service.name", "=~", "x)|(?:y"}], opts)
  end
end
