defmodule Pulse.Traces.SearchExpressionTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.SDKIngestHarness
  alias Pulse.Test.StringOnlyTempoSearchStorage
  alias Pulse.Traces.SearchExpression
  alias Pulse.Traces.SearchExpression.Evaluator
  alias Pulse.Traces.TempoSearch

  @fixture Path.expand("../../fixtures/traces/search_expressions", __DIR__)
  @opts [trace_start: 99_000_000_000, trace_end: 200_000_000_000, limit: 100, spss: 3]

  defp fixture do
    input = File.read!(Path.join(@fixture, "input.protobuf"))
    oracle = File.read!(Path.join(@fixture, "oracle.json"))
    assert sha(input) == "41a46730778cf44f0934d5084000fce1a2f79aa3e6e63ce22ccdac5f0a2dac58"
    assert sha(oracle) == "2e7d8723a134bd9007c86f114335ff8d21ea0853e70a1bbcf7261d4a0579eb4c"

    assert sha(File.read!(Path.join(@fixture, "produce.go.txt"))) ==
             "c428dc2994e756fe0fa87c678b6871932c62427286601040633871c2a6ca5893"

    assert {:ok, spans, 0} = Traces.decode_protobuf(input)
    assert length(spans) == 9
    {spans, Pulse.JSON.decode!(oracle)}
  end

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp normalize(response), do: Map.put_new(response, "traces", [])

  defp native(rows, program, opts \\ @opts) do
    {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

    {:ok, state} =
      NIF.tempo_expression_search_new(0, opts[:trace_start], opts[:trace_end], program, opts[:limit], opts[:spss])

    assert {:ok, _} = NIF.tempo_search_add(state, blob)
    NIF.tempo_search_finish(state)
  end

  test "actual Tempo 2.9 Parquet/TraceQL expressions agree with independent reference and native complete context" do
    {rows, cases} = fixture()
    assert length(cases) == 24

    for c <- cases do
      assert {:ok, {:expression, program} = expression} = TempoSearch.parse(c["query"])
      assert {:ok, actual} = native(rows, program)
      assert {:ok, reference} = TempoSearch.json(rows, expression, @opts)
      expected = normalize(c["response"])
      assert normalize(Pulse.JSON.decode!(actual)) === expected, c["query"]
      assert normalize(Pulse.JSON.decode!(reference)) === expected, c["query"]
    end
  end

  test "public Parquet engine unscoped search preserves span precedence, original types and both sampled owners" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
    input = File.read!(Path.join(dir, "search-input.protobuf"))
    oracle = File.read!(Path.join(dir, "search-oracle.json"))
    assert sha(input) == "dec8004d8460e2f487c50af8093acb71e2eebfcbad84a93b921ebe269d184ea0"
    assert sha(oracle) == "3b655f0433d4a93634098e89286a9c5c6db55e8ae8a6bda10e1ceb7d5d98c602"

    assert sha(File.read!(Path.join(dir, "produce_search.go.txt"))) ==
             "59e93879c6ff66167bef4470d36164da0c1bc17335a84af83d0dbf39ee6b79d3"

    assert {:ok, rows, 0} = Traces.decode_protobuf(input)
    cases = Pulse.JSON.decode!(oracle)
    assert length(cases) == 16
    assert length(rows) == 6
    Pulse.Runtime.put_env(:pulse, Storage, adapter: StringOnlyTempoSearchStorage)
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)
    assert :ok = Storage.append(:traces, "unscoped", rows)

    for c <- cases do
      opts = Keyword.merge(@opts, trace_start: c["Start"] * 1_000_000_000, trace_end: c["End"] * 1_000_000_000)
      assert {:ok, {:expression, program} = expression} = TempoSearch.parse(c["query"])
      assert {:ok, actual} = native(rows, program, opts)
      assert {:ok, reference} = TempoSearch.json(rows, expression, opts)
      assert {:ok, stored} = TempoSearch.query("unscoped", c["query"], opts)
      assert normalize(Pulse.JSON.decode!(actual)) === normalize(c["response"]), c["query"]
      assert normalize(Pulse.JSON.decode!(reference)) === normalize(c["response"]), c["query"]
      assert normalize(Pulse.JSON.decode!(stored)) === normalize(c["response"]), c["query"]

      if c["Start"] > 0 do
        args = %{
          "tenant" => "unscoped",
          "query" => c["query"],
          "start_ts_ns" => opts[:trace_start],
          "end_ts_ns" => opts[:trace_end]
        }

        assert {:ok, [%{"text" => json}]} = Tools.call("search_trace_metadata", args)
        assert normalize(Pulse.JSON.decode!(json)) === normalize(c["response"]), c["query"]
      end
    end
  end

  test "storage and MCP evaluate expressions without sending them to legacy string callbacks" do
    {rows, cases} = fixture()
    Pulse.Runtime.put_env(:pulse, Storage, adapter: StringOnlyTempoSearchStorage)
    assert :ok = Storage.append(:traces, "fixture", rows)
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for c <- cases do
      assert {:ok, json} = TempoSearch.query("fixture", c["query"], @opts)
      assert normalize(Pulse.JSON.decode!(json)) === normalize(c["response"])
    end

    c = Enum.at(cases, 3)

    args = %{
      "tenant" => "fixture",
      "query" => c["query"],
      "start_ts_ns" => @opts[:trace_start],
      "end_ts_ns" => @opts[:trace_end]
    }

    assert {:ok, [%{"text" => json}]} = Tools.call("search_trace_metadata", args)
    assert normalize(Pulse.JSON.decode!(json)) === normalize(c["response"])
  end

  @tag :tmp_dir
  test "authenticated local OTLP ingestion, S3 publication and HTTP/MCP expressions retain tenant and budget fences",
       ctx do
    {_, cases} = fixture()
    harness = SDKIngestHarness.start!(ctx.tmp_dir, ~w(fixture other))

    response =
      Req.post!(harness.api <> "/v1/traces",
        headers: [{"content-type", "application/x-protobuf"} | SDKIngestHarness.headers("fixture")],
        body: File.read!(Path.join(@fixture, "input.protobuf"))
      )

    assert response.status == 200

    for c <- cases do
      response =
        Req.get!(harness.api <> "/api/search",
          headers: SDKIngestHarness.headers("fixture"),
          params: [q: c["query"], start: 99, end: 200]
        )

      assert response.status == 200
      assert normalize(response.body) === normalize(c["response"]), c["query"]
    end

    query = Enum.at(cases, 3)["query"]

    response =
      Req.get!(harness.api <> "/api/search",
        headers: SDKIngestHarness.headers("other"),
        params: [q: query, start: 99, end: 200]
      )

    assert response.status == 200
    assert normalize(response.body) == %{"traces" => []}

    args = %{
      "tenant" => "fixture",
      "query" => query,
      "start_ts_ns" => @opts[:trace_start],
      "end_ts_ns" => @opts[:trace_end]
    }

    assert %{"result" => %{"content" => [%{"text" => json}]}} =
             SDKIngestHarness.mcp!(harness, "fixture", "search_trace_metadata", args)

    assert normalize(Pulse.JSON.decode!(json)) === normalize(Enum.at(cases, 3)["response"])

    assert %{"result" => %{"isError" => true}} =
             SDKIngestHarness.mcp!(harness, "other", "search_trace_metadata", args)

    assert {:error, :query_scan_limit} = TempoSearch.query("fixture", query, Keyword.put(@opts, :max_scan_rows, 8))
  end

  test "parentheses and TraceQL equal-precedence left association are preserved, not conventional AND precedence" do
    assert {:ok, {:expression, program}} =
             SearchExpression.parse("{status = ok || status = error && duration > 500ms} with (most_recent=true)")

    assert Enum.map(program, &elem(&1, 2)) == ["=", "=", "||", ">", "&&"]

    assert {:ok, {:expression, program}} =
             SearchExpression.parse("{status = ok || (status = error && duration > 500ms)} with (most_recent=true)")

    assert Enum.map(program, &elem(&1, 2)) == ["=", "=", ">", "&&", "||"]
  end

  test "fractional duration parsing uses the public TraceQL literal oracle and integer comparisons" do
    bytes = File.read!(Path.join(@fixture, "durations.json"))
    assert sha(bytes) == "4bf85da17b6a5fc161de716753b68476302bf6a3a745462118ff1b836e722262"

    for c <- Pulse.JSON.decode!(bytes) do
      result = SearchExpression.parse("{duration = " <> c["literal"] <> "} with (most_recent=true)")

      if c["accepted"] do
        assert {:ok, {:expression, [{"intrinsic", "duration", "=", nanos}]}} = result
        assert String.to_integer(nanos) == c["nanos"], c["literal"]
      else
        assert {:error, _} = result
      end
    end
  end

  test "documented group and predicate ceilings fit the tokenizer and JSON quoting is explicit" do
    grouped = String.duplicate("(", 16) <> "status = error" <> String.duplicate(")", 16)
    query = "{" <> Enum.join(List.duplicate(grouped, 16), " || ") <> "} with (most_recent=true)"
    assert {:ok, {:expression, program}} = SearchExpression.parse(query)
    assert length(program) == 31

    assert {:ok, {:expression, [{"span.string", "route", "!=", "/health"}]}} =
             SearchExpression.parse("{span.route != \"\\/health\"} with (most_recent=true)")

    for value <- ["a\tb", "\\x2fhealth"] do
      assert {:error, _} = SearchExpression.parse("{span.route != \"" <> value <> "\"} with (most_recent=true)")
    end
  end

  test "reference work budget charges nonmatches before returning false and validates direct programs" do
    {rows, _} = fixture()
    {:ok, {:expression, program}} = SearchExpression.parse("{status = error} with (most_recent=true)")
    {:ok, {:expression, compiled}} = Evaluator.prepare(program)
    assert {:error, :query_resource_limit} = Evaluator.evaluate(hd(rows), compiled, 20_000_000)

    for invalid <- [
          [nil],
          [{"boolean", "", "||", ""}],
          [{"intrinsic", "status", "=", "99"}],
          [{"intrinsic", "duration", ">", "-1"}]
        ] do
      assert {:error, _} = SearchExpression.validate(invalid)
    end
  end

  test "unsupported syntax, unclosed groups, macros, literals and hints reject whole" do
    for condition <- [
          "(status = error",
          "status = error)",
          "((status = error)",
          "status = error &&",
          "status = error || {}",
          "status >= error",
          "status = 2",
          "duration > 500",
          "duration > -1s",
          "duration > 9223372036854775808ns",
          "span.code >= 9223372036854775808",
          "span.code >= -9223372036854775809",
          "span.code >= 500.5",
          "resource.x = true",
          "span.x !~ 1",
          "! (status = error)",
          "status = error >> status = ok",
          "span.route !~ \"${route}\"",
          "trace:duration > 500ms"
        ] do
      assert {:error, _} = TempoSearch.parse("{" <> condition <> "} with (most_recent=true)"), condition
    end

    for hint <- [" with (most_recent=false)", " with (most_recent=true) garbage"] do
      assert {:error, _} = TempoSearch.parse("{status = error}" <> hint)
    end

    assert {:ok, {:expression, _}} = TempoSearch.parse("{status = error}")
  end

  test "leaf, regex, nesting, program and expression byte budgets reject without partial evaluation" do
    for {condition, reason} <- [
          {Enum.join(List.duplicate("status = error", 17), " || "), :query_expression_limit},
          {Enum.join(List.duplicate(~s(span.x !~ "x"), 9), " && "), :query_expression_limit},
          {String.duplicate("(", 17) <> "status = error" <> String.duplicate(")", 17), :query_expression_limit},
          {String.duplicate(" ", 16_385), :query_expression_limit}
        ] do
      assert {:error, ^reason} = SearchExpression.parse("{" <> condition <> "} with (most_recent=true)")
    end

    for program <- [
          [],
          [{"boolean", "", "||", ""}],
          [{"span.int", "code", ">=", "9223372036854775808"}],
          [{"intrinsic", "status", "=", "999"}],
          [{"span.string", "x", "!~", "(?=x)"}],
          [{"span.string", "x", "!~", "x"}, {"span.string", "x", "!~", "x"}]
        ] do
      assert :fallback = NIF.tempo_expression_search_new(0, @opts[:trace_start], @opts[:trace_end], program, 100, 3)
    end
  end

  test "candidate-first replay restores earlier roots and unfiltered complete service context across objects" do
    {rows, cases} = fixture()
    {:ok, {:expression, program} = expression} = TempoSearch.parse(Enum.at(cases, 19)["query"])
    {:ok, state} = NIF.tempo_expression_search_new(0, @opts[:trace_start], @opts[:trace_end], program, 100, 3)

    for row <- rows do
      {:ok, blob, _, _} = S3.encode_segment(:traces, [row])
      assert {:ok, 1} = NIF.tempo_search_add(state, blob)
    end

    assert {:ok, json} = NIF.tempo_search_finish(state)
    assert {:ok, reference} = TempoSearch.json(Enum.reverse(rows), expression, @opts)
    assert Pulse.JSON.decode!(json) === Pulse.JSON.decode!(reference)
    result = Pulse.JSON.decode!(json)
    trace = Enum.find(result["traces"], &(&1["traceID"] == "7"))
    assert trace["rootServiceName"] == "frontend"
    assert trace["durationMs"] == 2600
    assert map_size(trace["serviceStats"]) == 2
  end

  test "overlapping legacy uncertainty and corrupt nonmatches cannot be hidden behind a true OR branch" do
    {rows, cases} = fixture()
    {:ok, {:expression, program} = expression} = TempoSearch.parse(Enum.at(cases, 19)["query"])
    row = hd(rows)
    legacy = %{row | otlp: nil}
    assert {:error, :trace_metadata_unknown} = native([legacy | tl(rows)], program)
    assert {:error, :trace_metadata_unknown} = TempoSearch.json([legacy | tl(rows)], expression, @opts)
    corrupt = %{row | status: %{"code" => 99}}
    assert {:error, _} = TempoSearch.json([corrupt | tl(rows)], expression, @opts)
    assert {:error, _} = S3.encode_segment(:traces, [corrupt | tl(rows)])
  end
end
