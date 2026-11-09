defmodule Pulse.Traces.SearchExpressionTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Test.LegacyExpressionTempoStorage
  alias Pulse.Test.SDKIngestHarness
  alias Pulse.Test.StringOnlyTempoSearchStorage
  alias Pulse.Test.TempoSearchOracle
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

  test "pinned Tempo basic search engine/Parquet oracle agrees natively and through the bounded reference" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
    input = File.read!(Path.join(dir, "basic-search-input.protobuf"))
    oracle = File.read!(Path.join(dir, "basic-search-oracle.json"))
    assert sha(input) == "5815f74bae44f36b164a3708aa0d75c9542fe95d4db23c55cda67cdcccc6a704"
    assert sha(oracle) == "d425942e621d1147c5db51bc676f9a692d16a7b4c1e379efbf8c51be214232da"
    assert {:ok, rows, 0} = Traces.decode_protobuf(input)
    assert length(rows) == 14
    cases = Pulse.JSON.decode!(oracle)
    assert length(cases) == 48
    Pulse.Runtime.put_env(:pulse, Storage, adapter: StringOnlyTempoSearchStorage)
    assert :ok = Storage.append(:traces, "basic", rows)

    for c <- cases do
      assert {:ok, {:expression, program} = expression} = TempoSearch.parse(c["query"])
      assert {:ok, actual} = native(rows, program)
      assert {:ok, reference} = TempoSearch.json(rows, expression, @opts)
      assert {:ok, stored} = Storage.tempo_search_json("basic", expression, @opts)
      expected = TempoSearchOracle.response(c["response"])
      assert TempoSearchOracle.response(Pulse.JSON.decode!(actual)) === expected, c["query"]
      assert TempoSearchOracle.response(Pulse.JSON.decode!(reference)) === expected, c["query"]
      assert TempoSearchOracle.response(Pulse.JSON.decode!(stored)) === expected, c["query"]

      if SearchExpression.typed?(program) do
        Pulse.Runtime.put_env(:pulse, Storage, adapter: LegacyExpressionTempoStorage)
        assert {:ok, legacy} = Storage.tempo_search_json("basic", expression, @opts)
        assert TempoSearchOracle.response(Pulse.JSON.decode!(legacy)) === expected, c["query"]
        Pulse.Runtime.put_env(:pulse, Storage, adapter: StringOnlyTempoSearchStorage)
      end
    end
  end

  test "selecting intrinsic name fences old structural adapters even with an old string predicate" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
    assert {:ok, rows, 0} = dir |> Path.join("basic-search-input.protobuf") |> File.read!() |> Traces.decode_protobuf()
    Pulse.Runtime.put_env(:pulse, Storage, adapter: LegacyExpressionTempoStorage)
    assert :ok = Storage.append(:traces, "selected-name", rows)
    assert {:ok, {:expression, program} = expression} = TempoSearch.parse(~s|{span.name = "Bob"} \| select(name)|)
    assert SearchExpression.typed?(program)
    assert {:ok, actual} = Storage.tempo_search_json("selected-name", expression, @opts)
    assert {:ok, reference} = TempoSearch.json(rows, expression, @opts)
    assert actual == reference
    samples = actual |> Pulse.JSON.decode!() |> Map.fetch!("traces") |> Enum.flat_map(& &1["spanSet"]["spans"])
    assert Enum.any?(samples, &(&1["name"] == "hello"))

    assert Enum.all?(samples, fn sample ->
             Enum.filter(sample["attributes"], &(&1["key"] == "name")) ==
               [%{"key" => "name", "value" => %{"stringValue" => "Bob"}}]
           end)
  end

  @tag :intrinsic_search
  test "pinned Tempo full intrinsic and owner engine oracle agrees with native and reference search" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)
    input = File.read!(Path.join(dir, "intrinsics-input.protobuf"))
    assert sha(input) == "c1cbfcc6e3f68fdc37324b228ea79d78a862ac66f198a84283072dbafd638000"

    assert sha(File.read!(Path.join(dir, "intrinsics-input.json"))) ==
             "82b9b84f6653b7e9759afcf78b20bc8f460d382095d9f8b7a09b580fe612de8c"

    assert sha(File.read!(Path.join(dir, "produce_intrinsics.go.txt"))) ==
             "a689a0db28794d53edf9c70b1c3719740055bfefcf31df6d4221f43216433d1c"

    assert {:ok, rows, 0} = Traces.decode_protobuf(input)
    assert length(rows) == 6
    oracle = File.read!(Path.join(dir, "intrinsics-oracle.json"))
    assert sha(oracle) == "d7def6e45a5a4b759f8dc77b4c1f309db94679ebc99bb60d1d323cf05c8abb94"
    cases = Pulse.JSON.decode!(oracle)
    assert length(cases) == 76
    Pulse.Runtime.put_env(:pulse, Storage, adapter: LegacyExpressionTempoStorage)
    assert :ok = Storage.append(:traces, "intrinsics", rows)

    for c <- cases do
      assert c["error"] == nil, c["query"]
      assert {:ok, {:expression, program} = expression} = SearchExpression.parse(c["query"])
      assert {:ok, actual} = native(rows, program)
      assert {:ok, reference} = TempoSearch.json(rows, expression, @opts)
      expected = TempoSearchOracle.response(c["response"])

      assert TempoSearchOracle.response(Pulse.JSON.decode!(actual)) === expected,
             "native " <> c["query"] <> "\n" <> actual <> "\nexpected " <> inspect(expected, limit: :infinity)

      assert TempoSearchOracle.response(Pulse.JSON.decode!(reference)) === expected, "reference " <> c["query"]

      if SearchExpression.scoped?(program) do
        assert {:ok, fallback} = Storage.tempo_search_json("intrinsics", expression, @opts)
        assert TempoSearchOracle.response(Pulse.JSON.decode!(fallback)) === expected, "adapter " <> c["query"]
      end
    end
  end

  test "pinned ParseIdentifier quoted segments preserve their exact decoded key bytes" do
    # Unchanged rows from pkg/traceql/parse_test.go TestParseIdentifier.
    for {identifier, key} <- [
          {~S(."foo bar"), "foo bar"},
          {~S(."bar z".foo), "bar z.foo"},
          {~S(.foo."bar baz".bar), "foo.bar baz.bar"},
          {~S(span."bar z".foo), "bar z.foo"},
          {~S(resource."foo bar"), "foo bar"},
          {~S(.foo."bar \" baz"), "foo.bar \" baz"},
          {~S(.foo."bar \\ baz"), "foo.bar \\ baz"},
          {~S(."foo.bar"), "foo.bar"},
          {".😝", "😝"}
        ] do
      assert {:ok, {:expression, [{_, ^key, "=", "x"}]}} = SearchExpression.parse("{" <> identifier <> ~s| = "x"}|)

      assert {:ok, {:expression, [_, {"select", _, ^key, ""}]}} =
               SearchExpression.parse("{} | select(" <> identifier <> ")")
    end

    for key <- [~S(span."bad\n"), ~S(span."bad\u0020"), ~S(span."bad\x20"), ~S(span."unclosed)] do
      assert {:error, _} = SearchExpression.parse("{" <> key <> ~s| = "x"}|)
    end
  end

  test "shared context defers root ambiguity until a root predicate and charges original link attributes" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)

    assert {:ok, [root, child | _], 0} =
             dir |> Path.join("intrinsics-input.protobuf") |> File.read!() |> Traces.decode_protobuf()

    child = %{child | parent_span_id: nil}
    assert {:ok, contexts, work} = Evaluator.trace_context([root, child])

    assert work ==
             Enum.reduce([root, child], 0, fn row, work ->
               work + 2 + length(row.otlp["resource"]) + Enum.reduce(row.otlp["links"], 0, &(1 + length(&1) + &2))
             end)

    context = Map.fetch!(contexts, root.trace_id)
    assert context.root_conflict
    assert {:ok, {:expression, duration}} = SearchExpression.parse("{trace:duration > 2h}")
    assert {:ok, {:expression, duration}} = Evaluator.prepare(duration)
    assert {:ok, true, _, _, _} = Evaluator.evaluate_mask(root, Evaluator.with_context(duration, context), 0)
    assert {:ok, {:expression, named}} = SearchExpression.parse(~s|{rootName = "hello"}|)
    assert {:ok, {:expression, named}} = Evaluator.prepare(named)
    assert {:error, :trace_root_conflict} = Evaluator.evaluate_mask(root, Evaluator.with_context(named, context), 0)
    assert {:error, :query_resource_limit} = Evaluator.trace_context([root], 20_000_000 - 5)
  end

  test "quoted attribute keys named like intrinsics never request unrelated owner metadata" do
    for key <- ~w(event:name event:timeSinceStart link:spanID instrumentation:name) do
      assert {:ok, {:expression, program}} = SearchExpression.parse(~s|{span."#{key}" = "x"}|)
      assert [{"span.string", ^key, "=", "x"}] = program
      assert {:ok, {:expression, compiled}} = Evaluator.prepare(program)
      refute compiled.events or compiled.links or compiled.instrumentation or compiled.context
    end
  end

  test "root service predicates never promote absent or wrong original service types into known empty values" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)

    assert {:ok, [root | _], 0} =
             dir |> Path.join("intrinsics-input.protobuf") |> File.read!() |> Traces.decode_protobuf()

    assert {:ok, {:expression, program} = expression} = SearchExpression.parse(~s|{rootServiceName = ""}|)

    for attrs <- [[], [%{"key" => "service.name", "value" => %{"boolValue" => false}}]] do
      row = %{root | otlp: Map.put(root.otlp, "resource", attrs)}
      assert {:error, :trace_root_unknown} = TempoSearch.json([row], expression, @opts)
      assert {:error, :trace_root_unknown} = native([row], program)
    end
  end

  test "actual trace-duration engine oracle uses the entire trace in native/reference and legacy fallback" do
    dir = Path.expand("../../fixtures/traces/tempo_integration", __DIR__)

    assert {:ok, rows, 0} =
             dir |> Path.join("trace-duration-input.protobuf") |> File.read!() |> Traces.decode_protobuf()

    cases = dir |> Path.join("trace-duration-oracle.json") |> File.read!() |> Pulse.JSON.decode!()
    assert length(rows) == 5
    assert length(cases) == 20
    opts = Keyword.put(@opts, :trace_end, 8_000_000_000_000)
    Pulse.Runtime.put_env(:pulse, Storage, adapter: LegacyExpressionTempoStorage)
    assert :ok = Storage.append(:traces, "duration", rows)

    for c <- cases do
      assert {:ok, {:expression, program} = expression} = TempoSearch.parse(c["query"])
      assert {:ok, actual} = native(rows, program, opts)
      assert {:ok, reference} = TempoSearch.json(Enum.reverse(rows), expression, opts)
      expected = TempoSearchOracle.response(c["response"])
      assert TempoSearchOracle.response(Pulse.JSON.decode!(actual)) === expected, c["query"]
      assert TempoSearchOracle.response(Pulse.JSON.decode!(reference)) === expected, c["query"]

      if SearchExpression.trace_duration?(program) do
        assert {:ok, fallback} = Storage.tempo_search_json("duration", expression, opts)
        assert TempoSearchOracle.response(Pulse.JSON.decode!(fallback)) === expected

        # Memory's record sentinel rejects before the reference scan runs.
        assert {:error, :query_sample_limit} =
                 Storage.tempo_search_json("duration", expression, Keyword.put(opts, :max_scan_rows, 1))

        assert {:error, :trace_metadata_unknown} = TempoSearch.json([%{hd(rows) | otlp: nil}], expression, opts)
      end
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

  test "Grafana Drilldown root, true and nil-existence terms agree natively and in the reference" do
    span = fn trace, id, parent, attrs ->
      Map.merge(
        %{
          "traceId" => String.duplicate("0", 31) <> trace,
          "spanId" => String.duplicate("0", 15) <> id,
          "name" => "op",
          "kind" => 2,
          "startTimeUnixNano" => "150000000000",
          "endTimeUnixNano" => "150000001000",
          "attributes" => attrs
        },
        if(parent, do: %{"parentSpanId" => String.duplicate("0", 15) <> parent}, else: %{})
      )
    end

    resource = fn attrs, spans -> %{"resource" => %{"attributes" => attrs}, "scopeSpans" => [%{"spans" => spans}]} end
    service = fn name -> %{"key" => "service.name", "value" => %{"stringValue" => name}} end
    method = fn value -> [%{"key" => "http.method", "value" => value}] end
    region = %{"key" => "region", "value" => %{"stringValue" => "eu"}}

    # Trace 1 (region eu): typed int method on its root, string on its child.
    # Trace 2 (no region): attribute-free root, method only on its child.
    payload = %{
      "resourceSpans" => [
        resource.([service.("api"), region], [
          span.("1", "a", nil, method.(%{"intValue" => "1"})),
          span.("1", "b", "a", method.(%{"stringValue" => "GET"}))
        ]),
        resource.([service.("worker")], [
          span.("2", "c", nil, []),
          span.("2", "d", "c", method.(%{"stringValue" => "POST"}))
        ])
      ]
    }

    assert {:ok, rows, 0} = Traces.decode(payload)

    for {query, expected} <- [
          {"{true}", ~w(a b c d)},
          {"{nestedSetParent<0}", ~w(a c)},
          {"{nestedSetParent<0 && true && span.http.method != nil}", ~w(a)},
          {"{span.http.method = nil}", ~w(c)},
          {"{resource.region != nil}", ~w(a b)},
          {"{.http.method != nil && resource.region = nil}", ~w(d)}
        ] do
      assert {:ok, {:expression, program} = expression} = TempoSearch.parse(query)
      assert {:ok, actual} = native(rows, program)
      assert {:ok, reference} = TempoSearch.json(rows, expression, @opts)
      assert Pulse.JSON.decode!(actual) == Pulse.JSON.decode!(reference), query

      spans =
        for trace <- Pulse.JSON.decode!(actual)["traces"], span <- trace["spanSet"]["spans"] do
          String.trim_leading(span["spanID"], "0")
        end

      assert Enum.sort(spans) == expected, query
    end

    for query <- ["{event.x != nil}", "{span.x > nil}", "{nil}", "{nestedSetParent > 0}", "{true = span.x}"] do
      assert {:error, _} = SearchExpression.parse(query), query
    end
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
          "span.code >= 1e999",
          "resource.x > true",
          "span.x !~ 1",
          "! (status = error)",
          "status = error >> status = ok",
          "span.route !~ \"${route}\"",
          "trace:duration > -1s"
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
          [{"constant", "", "false", ""}],
          [{"span.float", "x", "=", "NaN"}],
          [{"span.float", "x", "=", "1e999"}],
          [{"span.bool", "x", ">", "true"}],
          [{"span.bool", "x", "=", "1"}],
          [{"intrinsic.string", "kind", "=", "client"}],
          [{"intrinsic", "kind", "=", "6"}],
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
