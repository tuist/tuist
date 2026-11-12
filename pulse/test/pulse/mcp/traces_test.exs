defmodule Pulse.MCP.TracesTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.MCP.Tools
  alias Pulse.OTLP.Traces
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.NativeQueryStorage
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  setup do
    Memory.reset()
    {:ok, spans, 0} = Traces.decode(Fixture.payload([Fixture.span(10), Fixture.span(20)]))
    :ok = Storage.append(:traces, "acme", spans)
    :ok
  end

  test "misspelled trace filters fail rather than silently broadening the query" do
    assert {:error, {:invalid_arguments, message}} =
             Tools.call("query_traces", %{"tenant" => "acme", "min_duraton_ns" => 5})

    assert message =~ "min_duraton_ns is not supported"
  end

  test "lookup and exact attribute filters share the bounded read-only registry" do
    tool = Enum.find(Tools.list(), &(&1["name"] == "query_traces"))
    assert tool["annotations"]["readOnlyHint"]
    assert Tools.known?("query_traces")

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_traces", %{
               "tenant" => "acme",
               "trace_id" => String.upcase(Fixture.trace_id()),
               "service" => "tuist-server",
               "attributes" => %{"auth_account_handle" => "acme", "metrics.skip" => false},
               "resource" => %{"deployment.environment" => "production"}
             })

    assert [%{"timestamp_ns" => 20}, %{"timestamp_ns" => 10}] = Pulse.JSON.decode!(text)
    assert {:ok, [%{"text" => "[]"}]} = Tools.call("query_traces", %{"tenant" => "other"})

    assert {:ok, [%{"text" => "[]"}]} =
             Tools.call("query_traces", %{"tenant" => "acme", "attributes" => %{"missing" => nil}})

    assert {:ok, [%{"text" => "[]"}]} =
             Tools.call("query_traces", %{"tenant" => "acme", "attributes" => %{"http.response.status_code" => 500.0}})

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_traces", %{"tenant" => "acme", "start_ts_ns" => 10, "end_ts_ns" => 10, "limit" => 1})

    assert [%{"timestamp_ns" => 10}] = Pulse.JSON.decode!(text)
  end

  test "native and reference resource regex predicates are fully anchored and typed" do
    for adapter <- [Memory, NativeQueryStorage] do
      Pulse.Runtime.put_env(:pulse, Storage, adapter: adapter)

      assert {:ok, [%{"text" => text}]} =
               Tools.call("query_traces", %{
                 "tenant" => "acme",
                 "resource" => %{"service.name" => "tuist-server"},
                 "resource_regex" => %{"deployment.environment" => "production|staging"},
                 "attributes_regex" => %{"auth_account_handle" => "a.*"}
               })

      assert length(Pulse.JSON.decode!(text)) == 2

      for filters <- [
            %{"resource_regex" => %{"deployment.environment" => "prod"}},
            %{"attributes_regex" => %{"metrics.skip" => ".*"}},
            %{"resource_regex" => %{"missing" => ".*"}}
          ] do
        assert {:ok, [%{"text" => "[]"}]} = Tools.call("query_traces", Map.put(filters, "tenant", "acme"))
      end
    end
  end

  test "regex Parquet selection matches reference on escaped, Unicode and typed metadata" do
    {:ok, [base], 0} = Traces.decode(Fixture.payload())

    values = [
      "production",
      "preproduction",
      "staging",
      "",
      "p\nr",
      "pä",
      "p\"quoted",
      "p\\slash",
      true,
      12,
      nil,
      %{},
      ["p"]
    ]

    rows =
      Enum.with_index(values)
      |> Enum.map(fn {value, index} ->
        %{
          base
          | timestamp_ns: index,
            end_timestamp_ns: index + 1,
            resource: Map.put(base.resource, "deployment.environment", value)
        }
      end)

    :ok = Memory.append(:traces, "regex-parity", rows)
    assert {:ok, blob, _, _} = S3.encode_segment(:traces, rows)

    for pattern <- [
          "prod.*",
          "production|staging",
          ".*",
          "",
          "^p.*",
          "(?i)PRODUCTION",
          "[[:alpha:]]+",
          "\\\\w+",
          "pä",
          ".*quoted"
        ] do
      opts = [resource_regex: %{"deployment.environment" => pattern}]
      assert {:ok, expected} = Memory.query(:traces, "regex-parity", opts)
      assert {:ok, actual} = S3.decode_segment(:traces, blob, nil, nil, opts)
      assert actual == expected, pattern
    end
  end

  test "regex syntax, types and aggregate pattern count fail before storage" do
    for value <- ["[", "(?=production)", String.duplicate("a", 1025), 12] do
      assert {:error, {:invalid_arguments, _}} =
               Tools.call("query_traces", %{"tenant" => "acme", "resource_regex" => %{"x" => value}})
    end

    assert {:error, {:invalid_arguments, _}} =
             Tools.call("query_traces", %{
               "tenant" => "acme",
               "resource_regex" => Map.new(1..5, &{Integer.to_string(&1), ".*"}),
               "attributes_regex" => Map.new(1..4, &{Integer.to_string(&1), ".*"})
             })
  end

  test "get_trace retains duplicates and conflicts without time-window truncation" do
    {:ok, [span], 0} = Traces.decode(Fixture.payload())
    root = %{span | parent_span_id: nil, span_id: String.duplicate("a", 16)}
    child = %{span | span_id: String.duplicate("b", 16), parent_span_id: String.duplicate("c", 16), timestamp_ns: 1}
    assert :ok = Storage.append(:traces, "assembled", [root, root, %{root | name: "conflict"}, child])
    tool = Enum.find(Tools.list(), &(&1["name"] == "get_trace"))
    assert tool["annotations"]["readOnlyHint"]

    assert {:ok, [%{"text" => text}]} =
             Tools.call("get_trace", %{"tenant" => "assembled", "trace_id" => String.upcase(span.trace_id)})

    result = Pulse.JSON.decode!(text)
    assert result["coverage"] == "all_stored_spans"
    assert result["span_count"] == 4
    assert result["root_span_ids"] == [root.span_id]
    assert result["duplicate_span_ids"] == [root.span_id]
    assert result["conflicting_span_ids"] == [root.span_id]
    assert result["missing_parent_span_ids"] == [child.parent_span_id]
    assert length(result["spans"]) == 4

    for field <- ["limit", "fields", "start_ts_ns", "end_ts_ns"] do
      assert {:error, {:invalid_arguments, _}} =
               Tools.call("get_trace", %{"tenant" => "assembled", "trace_id" => span.trace_id, field => 1})
    end

    assert {:ok, [%{"text" => missing}]} = Tools.call("get_trace", %{"tenant" => "other", "trace_id" => span.trace_id})
    assert Pulse.JSON.decode!(missing)["span_count"] == 0
  end

  test "slow/root/parent searches and projection remain bounded read-only queries" do
    {:ok, [span], 0} = Traces.decode(Fixture.payload([Fixture.span(30)]))
    root = %{span | parent_span_id: nil, end_timestamp_ns: 5030, span_id: String.duplicate("a", 16)}
    assert :ok = Storage.append(:traces, "acme", [root])

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_traces", %{
               "tenant" => "acme",
               "root_only" => true,
               "min_duration_ns" => 5000,
               "max_duration_ns" => 5000,
               "fields" => ["span_id", "duration_ns"]
             })

    assert [%{"span_id" => root.span_id, "duration_ns" => 5000}] == Pulse.JSON.decode!(text)

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_traces", %{
               "tenant" => "acme",
               "parent_span_id" => String.upcase(span.parent_span_id),
               "max_duration_ns" => 1000,
               "fields" => ["timestamp_ns"]
             })

    assert [%{"timestamp_ns" => 20}, %{"timestamp_ns" => 10}] == Pulse.JSON.decode!(text)
  end

  test "validates IDs, ranges, types and filters before querying" do
    for args <- [
          %{"trace_id" => "wrong"},
          %{"span_id" => String.duplicate("0", 16)},
          %{"kind" => 6},
          %{"root_only" => "true"},
          %{"min_duration_ns" => -1},
          %{"min_duration_ns" => 20, "max_duration_ns" => 10},
          %{"fields" => ["unknown"]},
          %{"parent_span_id" => "bad"},
          %{"status_code" => 3},
          %{"limit" => 5001},
          %{"attributes" => []},
          %{"attributes" => %{"k" => 18_446_744_073_709_551_616}},
          %{"start_ts_ns" => 10, "end_ts_ns" => 9},
          %{"attributes" => %{"k" => String.duplicate("x", 16_385)}}
        ] do
      assert {:error, {:invalid_arguments, _}} = Tools.call("query_traces", Map.put(args, "tenant", "acme"))
    end

    assert {:error, {:invalid_arguments, _}} = Tools.call("query_traces", %{})
  end

  test "authorization precedes remaining validation and calls without credentials fail closed" do
    hash = "sha256$" <> Base.encode16(:crypto.hash(:sha256, "secret"), case: :lower)
    Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{"acme" => hash})

    assert {:error, {:unauthorized, :missing_token}} =
             Tools.call("query_traces", %{"tenant" => "acme", "trace_id" => "wrong"})

    assert {:error, {:unauthorized, :missing_token}} =
             Tools.call("get_trace", %{"tenant" => "acme", "trace_id" => "wrong"})

    conn = Plug.Test.conn(:post, "/mcp") |> Plug.Conn.put_req_header("authorization", "Bearer secret")
    assert {:ok, _} = Tools.call("get_trace", %{"tenant" => "acme", "trace_id" => Fixture.trace_id()}, %{conn: conn})

    assert {:error, {:unauthorized, :unknown_tenant}} =
             Tools.call("get_trace", %{"tenant" => "other", "trace_id" => Fixture.trace_id()}, %{conn: conn})

    assert {:ok, _} = Tools.call("query_traces", %{"tenant" => "acme"}, %{conn: conn})

    assert {:error, {:unauthorized, :unknown_tenant}} =
             Tools.call("query_traces", %{"tenant" => "other"}, %{conn: conn})
  end

  test "unlimited responses fail explicitly above 5000, while explicit limits apply after filtering" do
    {:ok, [span], 0} = Traces.decode(Fixture.payload())
    :ok = Storage.append(:traces, "large", List.duplicate(span, 5001))
    assert {:error, :query_sample_limit} = Tools.call("query_traces", %{"tenant" => "large"})
    assert {:error, :query_sample_limit} = Tools.call("get_trace", %{"tenant" => "large", "trace_id" => span.trace_id})

    {:reply, response} =
      Pulse.MCP.dispatch(
        MCPMessages.request(1, "tools/call", %{
          "name" => "get_trace",
          "arguments" => %{"tenant" => "large", "trace_id" => span.trace_id}
        })
      )

    assert response["result"]["isError"]

    assert [%{"text" => ":query_sample_limit: the trace has more than 5,000 stored spans; use query_traces" <> _}] =
             response["result"]["content"]

    assert {:ok, [%{"text" => text}]} = Tools.call("query_traces", %{"tenant" => "large", "limit" => 2})
    assert length(Pulse.JSON.decode!(text)) == 2
  end
end
