defmodule Pulse.MCP.ToolsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.Codec.NIF
  alias Pulse.MCP.Tools
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.BlockingMetricStorage
  alias Pulse.Test.MCPMessages
  alias Pulse.Test.NativeQueryStorage
  alias Pulse.Traces.TempoSearch

  setup do
    Memory.reset()
    :ok
  end

  test "raw metric queries reject unbounded responses but honor an explicit result limit" do
    samples =
      for ts <- 1..5_001 do
        %MetricSample{timestamp_ns: ts, value: ts * 1.0, labels: %{"__name__" => "busy"}}
      end

    :ok = Storage.append(:metrics, "acme", samples)
    assert {:error, :query_sample_limit} = Tools.call("query_metrics", %{"tenant" => "acme"})
    assert {:ok, [%{"text" => text}]} = Tools.call("query_metrics", %{"tenant" => "acme", "limit" => 10})
    assert length(Pulse.JSON.decode!(text)) == 10
  end

  test "raw metric tools serialize non-finite storage values and PromQL tools use wire numbers" do
    values = [:stale, :nan, :infinity, :negative_infinity]

    samples =
      values
      |> Enum.with_index(1)
      |> Enum.map(fn {value, ts} ->
        %MetricSample{timestamp_ns: ts, value: value, labels: %{"__name__" => "special"}}
      end)

    :ok = Storage.append(:metrics, "acme", samples)
    assert {:ok, [%{"text" => raw}]} = Tools.call("query_metrics", %{"tenant" => "acme"})

    assert raw |> Pulse.JSON.decode!() |> Enum.map(& &1["value"]) |> Enum.sort() ==
             ["infinity", "nan", "negative_infinity", "stale"]

    assert {:ok, [%{"text" => evaluated}]} =
             Tools.call("query_promql", %{"tenant" => "acme", "query" => "vector(1 / 0)"})

    assert [entry] = Pulse.JSON.decode!(evaluated)["data"]["result"]
    assert Enum.at(entry["value"], 1) == "+Inf"
  end

  test "PromQL limit errors name the limit and its value" do
    samples = for ts <- 1..3, do: %MetricSample{timestamp_ns: ts, value: 1.0, labels: %{"__name__" => "busy"}}
    :ok = Storage.append(:metrics, "acme", samples)
    Pulse.Runtime.put_env(:pulse, Evaluator, max_samples: 2)

    assert {:error, :query_execution_limit} =
             Tools.call("query_promql", %{"tenant" => "acme", "query" => "busy", "end_ts_ns" => 3})

    assert %{limit: :max_samples, maximum: 2} = Pulse.QueryLimit.take()

    arguments = %{"tenant" => "acme", "query" => "busy", "end_ts_ns" => 3}

    assert {:reply, %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}}} =
             Pulse.MCP.dispatch(
               MCPMessages.request(1, "tools/call", %{"name" => "query_promql", "arguments" => arguments})
             )

    assert text =~ ":query_execution_limit: max_samples=2 exceeded"
    assert text =~ "PULSE_QUERY_MAX_SAMPLES"
  end

  test "trace tool resource failures preserve the worker limit instead of guessing a native limit" do
    adapter = BlockingMetricStorage
    Pulse.Runtime.put_env(:pulse, Storage, adapter: adapter)
    Pulse.Runtime.put_env(:pulse, adapter, self())
    Pulse.Runtime.put_env(:pulse, Pulse.QueryRunner, max_heap_words: 1_048_576)
    Pulse.Runtime.put_env(:pulse, TempoSearch, enabled: true)

    for {name, arguments} <- [
          {"query_traces", %{"tenant" => "acme", "limit" => 1}},
          {"search_trace_metadata",
           %{"tenant" => "acme", "query" => "{}", "start_ts_ns" => 1, "end_ts_ns" => 2, "limit" => 1}}
        ] do
      response =
        Pulse.Runtime.Task.async(fn ->
          Pulse.MCP.dispatch(MCPMessages.request(1, "tools/call", %{"name" => name, "arguments" => arguments}))
        end)

      assert_receive {:blocked_metric_query, worker, "acme"}, 5_000
      # QueryRunner classifies a killed worker as a resource failure and
      # records its configured heap limit, independently of native errors.
      Process.exit(worker, :kill)

      assert {:reply, %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}}} =
               Pulse.Runtime.Task.await(response)

      assert text =~ ":query_resource_limit: max_heap_mb=8 exceeded"
      assert text =~ "PULSE_QUERY_MAX_HEAP_MB"
      refute text =~ "16 MiB"
    end
  end

  test "queries that still hold Grafana's interval and range variables say how to replace them" do
    query = "sum by(instance) (rate(cache_prom_ex_phoenix_http_requests_total[$__rate_interval]))"

    assert {:error, {:invalid_arguments, message}} =
             Tools.call("query_promql", %{"tenant" => "acme", "query" => query})

    assert message =~ "Grafana's $__rate_interval"
    assert message =~ "[1m]"

    assert {:error, {:invalid_arguments, message}} =
             Tools.call("query_logql", %{"tenant" => "acme", "query" => ~s|count_over_time({job="x"}[${__interval}])|})

    assert message =~ "Grafana's $__interval,"

    # A Grafana-looking string inside a valid query is just a label value.
    assert {:ok, _} = Tools.call("query_promql", %{"tenant" => "acme", "query" => ~s|up{job="$__range"}|})

    assert {:error, {:invalid_arguments, :invalid_or_unsupported_query}} =
             Tools.call("query_promql", %{"tenant" => "acme", "query" => "rate(up[$window])"})
  end

  test "lists log, metric, trace and error query tools" do
    tools = Tools.list()
    names = Enum.map(tools, & &1["name"])
    assert "query_logs" in names
    assert "query_metrics" in names
    assert "discover_metrics" in names
    assert "query_logql" in names
    assert "query_promql" in names
    assert "query_errors" in names
    assert "list_error_issues" in names
    assert "list_error_changes" in names
    assert "list_indexed_error_issues" in names

    query_logs = Enum.find(tools, &(&1["name"] == "query_logs"))
    assert query_logs["inputSchema"]["required"] == ["tenant"]

    query_metrics = Enum.find(tools, &(&1["name"] == "query_metrics"))
    assert query_metrics["inputSchema"]["required"] == ["tenant"]

    query_logql = Enum.find(tools, &(&1["name"] == "query_logql"))
    assert query_logql["inputSchema"]["required"] == ["tenant", "query"]
  end

  describe "tool contracts" do
    test "discovery declares every query read-only" do
      {:reply, response} = Pulse.MCP.dispatch(MCPMessages.request(1, "tools/list"))

      tools =
        Enum.filter(response["result"]["tools"], fn tool ->
          String.starts_with?(tool["name"], "query_") or
            tool["name"] in ~w(list_error_issues list_error_changes list_indexed_error_issues)
        end)

      assert length(tools) == 9

      for tool <- tools do
        assert tool["annotations"] == %{
                 "readOnlyHint" => true,
                 "destructiveHint" => false,
                 "idempotentHint" => true,
                 "openWorldHint" => false
               }
      end
    end

    test "query tools reject malformed arguments and out-of-range timestamps" do
      for tool <- query_tools() do
        name = tool["name"]
        valid = %{"tenant" => "acme", "query" => expression(name)}

        for args <- [nil, [], "invalid", 1, %{}, %{"tenant" => nil}, %{"tenant" => ""}] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, args)
        end

        for field <- ["start_ts_ns", "end_ts_ns"],
            value <- ["10", 1.5, true, 9_223_372_036_854_775_808, -9_223_372_036_854_775_809] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(valid, field, value))
        end

        assert {:error, {:invalid_arguments, _}} =
                 Tools.call(name, Map.merge(valid, %{"start_ts_ns" => 20, "end_ts_ns" => 10}))
      end
    end

    test "limit boundaries apply to every tool advertising a limit" do
      for name <- ["query_logs", "query_metrics", "query_logql"] do
        valid = %{"tenant" => "acme", "query" => expression(name)}

        for value <- ["1", 1.5, 0, -1, 5001] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(valid, "limit", value))
        end

        for value <- [1, 5000] do
          assert {:ok, _} = Tools.call(name, Map.put(valid, "limit", value))
        end
      end
    end

    test "query strings and steps have consistent types and bounds" do
      for name <- ["query_logql", "query_promql"] do
        valid = %{"tenant" => "acme", "query" => expression(name)}

        for value <- [nil, 1, [], ""] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(valid, "query", value))
        end

        for value <- ["1", 1.5, 0, -1] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(valid, "step_ms", value))
        end
      end
    end

    test "rejects invalid service, direction, and nested matcher values" do
      assert {:error, {:invalid_arguments, _}} =
               Tools.call("query_logs", %{"tenant" => "acme", "service" => 1})

      for value <- [1, "sideways"] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_logql", %{
                   "tenant" => "acme",
                   "query" => expression("query_logql"),
                   "direction" => value
                 })
      end

      for matchers <- [
            %{},
            [nil],
            [%{}],
            [%{"name" => 1, "op" => "=", "value" => "x"}],
            [%{"name" => "a", "op" => "=", "value" => nil}],
            [%{"name" => "a", "op" => "???", "value" => "x"}]
          ] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_metrics", %{"tenant" => "acme", "matchers" => matchers})
      end
    end

    test "Prometheus range queries require both times and a step" do
      for fields <- [
            %{"start_ts_ns" => 0},
            %{"step_ms" => 1},
            %{"start_ts_ns" => 0, "end_ts_ns" => 10},
            %{"end_ts_ns" => 10, "step_ms" => 1}
          ] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_promql", Map.merge(%{"tenant" => "acme", "query" => "up"}, fields))
      end

      assert {:ok, _} =
               Tools.call("query_promql", %{
                 "tenant" => "acme",
                 "query" => "up",
                 "start_ts_ns" => 0,
                 "end_ts_ns" => 1_000_000,
                 "step_ms" => 1
               })
    end

    test "invalid argument values return a tool error through the dispatcher" do
      {:reply, response} =
        Pulse.MCP.dispatch(
          MCPMessages.request(1, "tools/call", %{
            "name" => "query_logs",
            "arguments" => %{"tenant" => "acme", "limit" => "bad"}
          })
        )

      assert response["result"]["isError"]
      assert [%{"type" => "text", "text" => text}] = response["result"]["content"]
      assert text =~ "invalid_arguments"
    end

    test "non-object arguments are invalid params, not tool errors" do
      for arguments <- [nil, [], "invalid", 1] do
        {:reply, response} =
          Pulse.MCP.dispatch(MCPMessages.request(1, "tools/call", %{"name" => "query_logs", "arguments" => arguments}))

        assert response["error"]["code"] == -32_602
      end
    end

    test "omitted optional fields and extra fields preserve existing calls" do
      for name <- ["query_logs", "query_metrics", "query_logql", "query_promql"] do
        assert {:ok, _} =
                 Tools.call(name, %{
                   "tenant" => "acme",
                   "query" => expression(name),
                   "future_option" => true
                 })
      end
    end

    test "optional nulls preserve defaults while required nulls are rejected" do
      for tool <- query_tools() do
        args = query_arguments(tool["name"])
        required = tool["inputSchema"]["required"]
        args = if "start_ts_ns" in required, do: Map.merge(args, %{"start_ts_ns" => 0, "end_ts_ns" => 0}), else: args

        for {field, _schema} <- tool["inputSchema"]["properties"], field not in required do
          assert {:ok, _} = Tools.call(tool["name"], Map.put(args, field, nil))
        end
      end
    end

    test "integer-valued decimal numbers follow the published integer schema" do
      for name <- ["query_logs", "query_metrics", "query_logql", "query_promql"] do
        args = %{"tenant" => "acme", "query" => expression(name), "end_ts_ns" => 1_000_000.0}
        assert {:ok, _} = Tools.call(name, args)
      end

      assert {:ok, _} = Tools.call("query_logs", %{"tenant" => "acme", "limit" => 1.0})

      assert {:ok, _} =
               Tools.call("query_promql", %{
                 "tenant" => "acme",
                 "query" => "up",
                 "start_ts_ns" => 0.0,
                 "end_ts_ns" => 1_000_000.0,
                 "step_ms" => 1.0
               })
    end

    test "tool schemas only use enforced validation keywords" do
      for tool <- Tools.list(), do: assert_supported_schema(tool["inputSchema"])
    end

    test "step conversion stays inside signed nanoseconds" do
      for name <- ["query_logql", "query_promql"] do
        args = %{"tenant" => "acme", "query" => expression(name), "start_ts_ns" => 0, "end_ts_ns" => 0}
        assert {:ok, _} = Tools.call(name, Map.put(args, "step_ms", 9_223_372_036_854))
        assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "step_ms", 9_223_372_036_855))
      end
    end

    test "metric regular expressions fail explicitly before storage, with or without samples" do
      for samples <- [[], [%MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"__name__" => "up"}}]] do
        Memory.reset()
        :ok = Storage.append(:metrics, "acme", samples)

        for op <- ["=~", "!~"], pattern <- ["(", "[", String.duplicate("x", 1025)] do
          assert {:error, {:invalid_arguments, _}} =
                   Tools.call("query_metrics", %{
                     "tenant" => "acme",
                     "matchers" => [%{"name" => "__name__", "op" => op, "value" => pattern}]
                   })
        end
      end

      assert {:ok, _} =
               Tools.call("query_metrics", %{
                 "tenant" => "acme",
                 "matchers" => [%{"name" => "__name__", "op" => "=~", "value" => "u.*"}]
               })

      for op <- ["=~", "!~"] do
        assert {:ok, _} =
                 Tools.call("query_metrics", %{
                   "tenant" => "acme",
                   "matchers" => [%{"name" => "__name__", "op" => op, "value" => String.duplicate("x", 1024)}]
                 })
      end
    end

    test "log metric ranges reject excessive steps before constructing the timeline" do
      for finish <- [11_000_000_000, 9_000_000_000_000_000_000] do
        assert {:error, _} =
                 Tools.call("query_logql", %{
                   "tenant" => "acme",
                   "query" => ~s|rate({service="api"}[5m])|,
                   "start_ts_ns" => 0,
                   "end_ts_ns" => finish,
                   "step_ms" => 1
                 })
      end
    end

    test "log and metric tools handle signed timestamp boundaries, including native decoding" do
      minimum = -9_223_372_036_854_775_808
      maximum = 9_223_372_036_854_775_807
      records = for ts <- [minimum, -1, maximum], do: %Log{timestamp_ns: ts, service: "api", body: "entry"}

      samples =
        for ts <- [minimum, -1, maximum], do: %MetricSample{timestamp_ns: ts, value: 1.0, labels: %{"__name__" => "up"}}

      :ok = Storage.append(:logs, "acme", records)
      :ok = Storage.append(:metrics, "acme", samples)

      {:ok, log_blob, _, _, _} = NIF.encode_log_segment_parquet(records)
      {:ok, metric_blob, _, _, _} = NIF.encode_metric_segment_parquet(samples)
      Pulse.Runtime.put_env(:pulse, Storage, adapter: NativeQueryStorage)

      for ts <- [minimum, -1, maximum] do
        assert {:ok, [_]} = NIF.decode_log_segment_parquet(log_blob, max(ts - 1, minimum), ts, nil, [], [])
        assert {:ok, [_]} = NIF.decode_metric_segment_parquet(metric_blob, max(ts - 1, minimum), ts, [])

        for tool <- query_tools(), tool["name"] != "query_errors" do
          assert {:ok, _} =
                   Tools.call(tool["name"], Map.put(query_arguments(tool["name"]), "end_ts_ns", ts))
        end

        assert {:ok, [%{"text" => text}]} =
                 Tools.call("query_promql", %{"tenant" => "acme", "query" => "up", "end_ts_ns" => ts})

        assert length(JSON.decode!(text)["data"]["result"]) == 1

        assert {:ok, _} =
                 Tools.call("query_logql", %{
                   "tenant" => "acme",
                   "query" => ~s|count_over_time({service="api"}[1s])|,
                   "end_ts_ns" => ts
                 })
      end

      for fields <- [%{}, %{"start_ts_ns" => minimum, "step_ms" => 1}] do
        args =
          Map.merge(
            %{
              "tenant" => "acme",
              "query" => ~s|count_over_time({service="api"}[1s] offset 1s)|,
              "end_ts_ns" => minimum
            },
            fields
          )

        assert {:ok, [%{"text" => text}]} = Tools.call("query_logql", args)
        assert JSON.decode!(text)["data"]["result"] == []
      end

      assert {:ok, [%{"text" => text}]} =
               Tools.call("query_promql", %{
                 "tenant" => "acme",
                 "query" => "up offset 1s",
                 "end_ts_ns" => minimum
               })

      assert JSON.decode!(text)["data"]["result"] == []
    end

    test "unknown tools keep their existing error" do
      assert {:error, {:unknown_tool, "missing"}} = Tools.call("missing", %{})
    end
  end

  defp assert_supported_schema(schema) do
    supported =
      ~w(type properties required items enum minimum maximum minLength maxLength maxItems maxProperties propertyNames description additionalProperties)

    case schema["additionalProperties"] do
      child when is_map(child) -> assert_supported_schema(child)
      value -> assert value in [nil, true, false]
    end

    if schema["propertyNames"], do: assert_supported_schema(schema["propertyNames"])
    assert Map.keys(schema) -- supported == []
    for {_name, child} <- schema["properties"] || %{}, do: assert_supported_schema(child)
    if schema["items"], do: assert_supported_schema(schema["items"])
  end

  defp query_arguments("query_traces"), do: %{"tenant" => "acme"}
  defp query_arguments(name), do: %{"tenant" => "acme", "query" => expression(name)}

  defp expression("query_logql"), do: ~s({service="api"})
  defp expression(_), do: "up"

  describe "argument validation" do
    @queries [
      {"query_logs", %{"tenant" => "acme"}},
      {"query_metrics", %{"tenant" => "acme"}},
      {"query_traces", %{"tenant" => "acme"}},
      {"query_logql", %{"tenant" => "acme", "query" => ~s({service="api"})}},
      {"query_promql", %{"tenant" => "acme", "query" => "up"}},
      {"query_errors", %{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => 100}},
      {"list_error_issues", %{"tenant" => "acme", "start_ts_ns" => 0, "end_ts_ns" => 100}}
    ]

    test "all advertised query tools declare read-only behavior" do
      assert length(query_tools()) == 6
      assert Enum.all?(query_tools(), &(&1["annotations"]["readOnlyHint"] == true))
    end

    test "rejects non-object arguments and invalid tenants across all tools" do
      for {name, args} <- @queries do
        assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.delete(args, "tenant"))

        if Map.has_key?(args, "query") do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.delete(args, "query"))
        end

        for invalid <- [nil, [], "acme", 42] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, invalid)
        end

        for invalid <- [nil, [], 42, true] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "tenant", invalid))
        end
      end
    end

    test "rejects malformed and reversed time bounds across all tools" do
      for {name, args} <- @queries do
        for key <- ["start_ts_ns", "end_ts_ns"],
            invalid <- ["10", 1.5, [], true, -9_223_372_036_854_775_809, 9_223_372_036_854_775_808] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, key, invalid))
        end

        assert {:error, {:invalid_arguments, _}} =
                 Tools.call(name, Map.merge(args, %{"start_ts_ns" => 20, "end_ts_ns" => 10}))
      end
    end

    test "enforces record limits for supplied values" do
      for {name, args} <- @queries, name != "query_promql" do
        for invalid <- [0, -1, 5001, "1", 1.5, true] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "limit", invalid))
        end

        for limit <- [1, 5000] do
          assert {:ok, _} = Tools.call(name, Map.put(args, "limit", limit))
        end
      end
    end

    test "rejects invalid query strings, steps, directions, and services" do
      for {name, args} <- @queries, name in ["query_logql", "query_promql"] do
        for invalid <- [nil, [], 42, true] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "query", invalid))
        end

        for invalid <- [0, -1, "1000", 1.5, true] do
          assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "step_ms", invalid))
        end
      end

      for invalid <- ["sideways", 1, true] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_logql", %{"tenant" => "acme", "query" => ~s({service="api"}), "direction" => invalid})
      end

      for invalid <- [1, [], true] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_logs", %{"tenant" => "acme", "service" => invalid})
      end
    end

    test "validates nested matchers without rejecting empty matcher values" do
      for invalid <- [
            %{},
            "up",
            [nil],
            [%{}],
            [%{"name" => 1, "op" => "=", "value" => "api"}],
            [%{"name" => "svc", "op" => "???", "value" => "api"}],
            [%{"name" => "svc", "op" => "=", "value" => nil}]
          ] do
        assert {:error, {:invalid_arguments, _}} =
                 Tools.call("query_metrics", %{"tenant" => "acme", "matchers" => invalid})
      end

      for op <- ["=", "!=", "=~", "!~"] do
        assert {:ok, _} =
                 Tools.call("query_metrics", %{
                   "tenant" => "acme",
                   "matchers" => [%{"name" => "svc", "op" => op, "value" => ""}]
                 })
      end
    end

    test "accepts equal bounds and empty matchers; only open schemas allow additional properties" do
      for {name, args} <- @queries do
        args = Map.merge(args, %{"start_ts_ns" => 10, "end_ts_ns" => 10})
        args = if name == "query_promql", do: Map.put(args, "step_ms", 1), else: args
        assert {:ok, _} = Tools.call(name, args)
        extended = Map.put(args, "extension", true)

        if name == "query_traces" do
          assert {:error, {:invalid_arguments, "arguments.extension is not supported"}} = Tools.call(name, extended)
        else
          assert {:ok, _} = Tools.call(name, extended)
        end
      end

      assert {:ok, _} = Tools.call("query_metrics", %{"tenant" => "acme", "matchers" => []})
    end

    test "normalizes integral numbers before execution" do
      for {name, args} <- @queries do
        args = Map.merge(args, %{"start_ts_ns" => 10.0, "end_ts_ns" => 10.0})
        args = if name == "query_promql", do: Map.put(args, "step_ms", 1.0), else: args
        args = if name == "query_promql", do: args, else: Map.put(args, "limit", 1.0)
        assert {:ok, _} = Tools.call(name, args)
      end
    end

    test "reports the failing argument path" do
      assert {:error, {:invalid_arguments, "arguments.limit must be at most 5000"}} =
               Tools.call("query_logs", %{"tenant" => "acme", "limit" => 5001})

      assert {:error, {:invalid_arguments, "arguments.matchers[0].value must be string"}} =
               Tools.call("query_metrics", %{
                 "tenant" => "acme",
                 "matchers" => [%{"name" => "svc", "op" => "=", "value" => nil}]
               })
    end

    test "valid arguments still require tenant authorization across all tools" do
      Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{})

      for {name, args} <- @queries do
        assert {:error, {:unauthorized, :missing_token}} = Tools.call(name, args)
        assert {:error, {:invalid_arguments, _}} = Tools.call(name, Map.put(args, "tenant", nil))
      end
    end

    test "unknown tools retain their error even with malformed arguments" do
      assert {:error, {:unknown_tool, "unknown"}} = Tools.call("unknown", nil)
    end

    test "the dispatcher exposes annotations and returns validation errors" do
      assert {:reply, %{"result" => %{"tools" => tools}}} =
               Pulse.MCP.dispatch(MCPMessages.request(1, "tools/list"))

      queries = Enum.filter(tools, &String.starts_with?(&1["name"], "query_"))
      assert Enum.all?(queries, &(&1["annotations"]["readOnlyHint"] == true))

      for {name, args} <- @queries do
        assert {:reply, %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}}} =
                 Pulse.MCP.dispatch(
                   MCPMessages.request(2, "tools/call", %{
                     "name" => name,
                     "arguments" => Map.put(args, "end_ts_ns", "bad")
                   })
                 )

        assert text =~ "invalid_arguments"
      end
    end
  end

  describe "query_promql" do
    test "evaluates stored metrics and rejects invalid steps" do
      :ok =
        Storage.append(:metrics, "acme", [
          %MetricSample{timestamp_ns: 1_000_000_000, value: 2.0, labels: %{"__name__" => "gauge"}}
        ])

      assert {:ok, [%{"text" => text}]} =
               Tools.call("query_promql", %{
                 "tenant" => "acme",
                 "query" => "sum(gauge)",
                 "end_ts_ns" => 1_000_000_000
               })

      assert JSON.decode!(text)["data"]["result"] == [%{"metric" => %{}, "value" => [1.0, "2"]}]

      assert {:error, {:invalid_arguments, _}} =
               Tools.call("query_promql", %{
                 "tenant" => "acme",
                 "query" => "gauge",
                 "step_ms" => 0
               })
    end

    test "requires tenant authorization before parsing or reading" do
      Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{})
      assert {:error, {:unauthorized, _}} = Tools.call("query_promql", %{"tenant" => "acme", "query" => "gauge"})
    end
  end

  describe "query_logql" do
    @tag :loki_scalars_batch
    test "scalar literals and vectors retain distinct wire types without log data" do
      for {query, kind, result} <- [
            {"0x1.8p3", "scalar", [60.0, "12"]},
            {"7 > 2", "scalar", [60.0, "1"]},
            {"10 / 0", "scalar", [60.0, "NaN"]},
            {"vector(2)", "vector", [%{"metric" => %{}, "value" => [60.0, "2"]}]}
          ] do
        assert {:ok, [%{"text" => text}]} =
                 Tools.call("query_logql", %{"tenant" => "acme", "query" => query, "end_ts_ns" => 60_000_000_000})

        assert JSON.decode!(text) == %{
                 "status" => "success",
                 "data" => %{"resultType" => kind, "result" => result, "stats" => %{}}
               }
      end
    end

    test "returns a Loki-shaped streams envelope for a log query" do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{timestamp_ns: 10, service: "api", body: "timeout"},
          %Log{timestamp_ns: 20, service: "api", body: "ok"}
        ])

      assert {:ok, [%{"type" => "text", "text" => text}]} =
               Tools.call("query_logql", %{
                 "tenant" => "acme",
                 "query" => ~s({service="api"} |= "timeout")
               })

      envelope = JSON.decode!(text)
      assert envelope["status"] == "success"
      assert envelope["data"]["resultType"] == "streams"
      streams = envelope["data"]["result"]
      lines = for %{"values" => vs} <- streams, [_ts, line] <- vs, do: line
      assert lines == ["timeout"]
    end

    test "returns a matrix envelope for a range metric query" do
      :ok =
        Storage.append(:logs, "acme", [
          %Log{timestamp_ns: 1_000_000_000, service: "api", body: "a"},
          %Log{timestamp_ns: 2_000_000_000, service: "api", body: "b"},
          %Log{timestamp_ns: 3_000_000_000, service: "api", body: "c"}
        ])

      assert {:ok, [%{"text" => text}]} =
               Tools.call("query_logql", %{
                 "tenant" => "acme",
                 "query" => "count_over_time({service=\"api\"}[1s])",
                 "start_ts_ns" => 1_000_000_000,
                 "end_ts_ns" => 3_000_000_000,
                 "step_ms" => 1000
               })

      envelope = JSON.decode!(text)
      assert envelope["data"]["resultType"] == "matrix"
    end

    test "surfaces LogQL parse errors" do
      assert {:error, {:invalid_arguments, {:logql_parse_error, _}}} =
               Tools.call("query_logql", %{"tenant" => "acme", "query" => "not a query"})
    end

    test "errors on missing tenant or query" do
      assert {:error, {:invalid_arguments, _}} = Tools.call("query_logql", %{})
      assert {:error, {:invalid_arguments, _}} = Tools.call("query_logql", %{"tenant" => "acme"})
    end
  end

  test "query_logs returns records for the tenant" do
    :ok =
      Storage.append(:logs, "acme", [
        %Log{timestamp_ns: 10, service: "api", body: "one"},
        %Log{timestamp_ns: 20, service: "web", body: "two"}
      ])

    assert {:ok, [%{"type" => "text", "text" => text}]} = Tools.call("query_logs", %{"tenant" => "acme"})
    assert [%{"body" => "two"}, %{"body" => "one"}] = JSON.decode!(text)
  end

  test "query_logs applies service and limit filters" do
    :ok =
      Storage.append(:logs, "acme", [
        %Log{timestamp_ns: 10, service: "api", body: "a"},
        %Log{timestamp_ns: 20, service: "web", body: "b"},
        %Log{timestamp_ns: 30, service: "api", body: "c"}
      ])

    assert {:ok, [%{"text" => text}]} =
             Tools.call("query_logs", %{"tenant" => "acme", "service" => "api", "limit" => 1})

    assert [%{"body" => "c", "service" => "api"}] = JSON.decode!(text)
  end

  test "query_logs errors when tenant is missing" do
    assert {:error, {:invalid_arguments, _}} = Tools.call("query_logs", %{})
  end

  describe "query_metrics" do
    test "returns samples for the tenant filtered by label matchers" do
      :ok =
        Storage.append(:metrics, "acme", [
          %MetricSample{timestamp_ns: 10, value: 1.0, labels: %{"__name__" => "up", "svc" => "api"}},
          %MetricSample{timestamp_ns: 20, value: 2.0, labels: %{"__name__" => "up", "svc" => "web"}}
        ])

      assert {:ok, [%{"type" => "text", "text" => text}]} =
               Tools.call("query_metrics", %{
                 "tenant" => "acme",
                 "matchers" => [%{"name" => "svc", "op" => "=", "value" => "api"}]
               })

      assert [sample] = JSON.decode!(text)
      assert sample["labels"]["svc"] == "api"
      assert sample["value"] == 1.0
    end

    test "errors on an unknown matcher op" do
      assert {:error, {:invalid_arguments, _}} =
               Tools.call("query_metrics", %{
                 "tenant" => "acme",
                 "matchers" => [%{"name" => "svc", "op" => "???", "value" => "api"}]
               })
    end

    test "errors when tenant is missing" do
      assert {:error, {:invalid_arguments, _}} = Tools.call("query_metrics", %{})
    end
  end

  describe "auth on the read path" do
    setup do
      hex = Base.encode16(:crypto.hash(:sha256, "the-token"), case: :lower)

      Pulse.Runtime.put_env(:pulse, Pulse.Auth,
        module: SharedSecret,
        tokens: %{"acme" => "sha256$#{hex}"}
      )

      :ok
    end

    test "rejects a query_logs call with no bearer token" do
      Storage.append(:logs, "acme", [%Log{timestamp_ns: 1}])

      assert {:error, {:unauthorized, :missing_token}} =
               Tools.call("query_logs", %{"tenant" => "acme"}, %{conn: %Plug.Conn{}})
    end

    test "fails closed when no conn is passed at all" do
      # Previous version had a "no conn = allow" fallback for in-process
      # callers. That was a bypass: any code path that forgot the context
      # would silently read another tenant's data under shared-secret
      # auth. Now the fallback constructs an empty %Plug.Conn{}, which
      # SharedSecret.verify sees as :missing_token.
      Storage.append(:logs, "acme", [%Log{timestamp_ns: 1}])

      assert {:error, {:unauthorized, :missing_token}} =
               Tools.call("query_logs", %{"tenant" => "acme"}, %{})
    end

    test "rejects a query_logs call with a bad token" do
      Storage.append(:logs, "acme", [%Log{timestamp_ns: 1}])

      conn = %Plug.Conn{} |> Plug.Conn.put_req_header("authorization", "Bearer wrong")

      assert {:error, {:unauthorized, :invalid_token}} =
               Tools.call("query_logs", %{"tenant" => "acme"}, %{conn: conn})
    end

    test "accepts a query_logs call with the correct token" do
      Storage.append(:logs, "acme", [%Log{timestamp_ns: 1, body: "ok"}])

      conn = %Plug.Conn{} |> Plug.Conn.put_req_header("authorization", "Bearer the-token")

      assert {:ok, [%{"text" => text}]} =
               Tools.call("query_logs", %{"tenant" => "acme"}, %{conn: conn})

      assert [%{"body" => "ok"}] = JSON.decode!(text)
    end
  end

  defp query_tools, do: Enum.filter(Tools.list(), &String.starts_with?(&1["name"], "query_"))
end
