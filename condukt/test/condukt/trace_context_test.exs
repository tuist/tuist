defmodule Condukt.TraceContextTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider
  alias Condukt.TraceContext
  alias ReqLLM.ToolCall

  defmodule Agent do
    use Condukt
  end

  defmodule ChildAgent do
    use Condukt
  end

  defmodule ParentAgent do
    use Condukt
  end

  test "extracts World Wide Web Consortium trace headers without an OpenTelemetry dependency" do
    assert {:ok, extracted} =
             TraceContext.from_headers([
               {"TraceParent", "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"},
               {"TraceState", "vendor=value"},
               {"Baggage", "upstream=value"}
             ])

    assert extracted == context()
  end

  test "accepts unsampled and forward-compatible trace headers" do
    trace_id = "0123456789abcdef0123456789abcdef"
    span_id = "0123456789abcdef"

    assert %TraceContext{flags: "00"} = TraceContext.new(trace_id: trace_id, span_id: span_id, flags: "00")

    assert {:ok, %TraceContext{trace_id: ^trace_id, span_id: ^span_id, flags: "00"}} =
             TraceContext.from_headers([{"traceparent", "00-#{trace_id}-#{span_id}-00"}])

    assert {:ok, %TraceContext{trace_id: ^trace_id, span_id: ^span_id, flags: "00"}} =
             TraceContext.from_headers([{"traceparent", "01-#{trace_id}-#{span_id}-00-extra"}])
  end

  test "rejects invalid trace context options" do
    assert_raise ArgumentError, ~r/trace_context must be/, fn ->
      TraceContext.capture(trace_context: :invalid)
    end
  end

  test "percent-encodes the session identifier in baggage" do
    headers = TraceContext.headers(context(), "session id/a+b")

    assert header(headers, "baggage") == "upstream=value,condukt.session.id=session%20id%2Fa%2Bb"
  end

  test "clears a previously attached context when attaching nil" do
    TraceContext.put_current(context())

    assert :ok = TraceContext.attach(nil)
    assert is_nil(TraceContext.current())
  end

  test "injects trace context, session grouping, and caller headers into normal requests" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])

    {:ok, agent} =
      Agent.start_link(
        id: "parent-session",
        model: model,
        llm_request_options: [
          temperature: 0.2,
          req_http_options: [headers: [{"x-tenant", "atlas"}, {"baggage", "tenant=atlas"}]]
        ],
        load_project_instructions: false
      )

    trace_context = %{context() | baggage: "upstream=value,tenant=from-context"}

    assert {:ok, "done"} = Condukt.run(agent, "go", trace_context: trace_context)

    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    assert opts[:temperature] == 0.2

    headers = headers(opts)
    assert {"x-tenant", "atlas"} in headers
    assert header(headers, "tracestate") == "vendor=value"
    assert header(headers, "baggage") == "tenant=atlas,upstream=value,condukt.session.id=parent-session"

    traceparent = header(headers, "traceparent")
    assert ["00", "0123456789abcdef0123456789abcdef", span_id, "01"] = String.split(traceparent, "-")
    assert span_id != trace_context.span_id

    GenServer.stop(agent)
  end

  test "propagates trace context through both one-shot call shapes" do
    {module_model, module_model_id} = LLMProvider.model([LLMProvider.text_response("module done")])

    assert {:ok, "module done"} =
             Condukt.run(Agent, "go",
               id: "module-session",
               model: module_model,
               trace_context: context(),
               load_project_instructions: false
             )

    assert_receive {LLMProvider, :request, ^module_model_id, _context, module_opts}
    assert header(headers(module_opts), "baggage") =~ "condukt.session.id=module-session"

    {anonymous_model, anonymous_model_id} = LLMProvider.model([LLMProvider.text_response("anonymous done")])

    assert {:ok, "anonymous done"} =
             Condukt.run("go",
               id: "anonymous-session",
               model: anonymous_model,
               trace_context: context(),
               load_project_instructions: false
             )

    assert_receive {LLMProvider, :request, ^anonymous_model_id, _context, anonymous_opts}
    assert header(headers(anonymous_opts), "baggage") =~ "condukt.session.id=anonymous-session"
  end

  test "allows one-shot runs to disable a calling process trace context" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])

    TraceContext.put_current(context())
    on_exit(&TraceContext.clear_current/0)

    assert {:ok, "done"} =
             Condukt.run("go",
               model: model,
               trace_context: false,
               load_project_instructions: false
             )

    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    refute opts[:req_http_options]
  end

  test "handles nil request options and preserves multi-value headers" do
    {nil_model, nil_model_id} = LLMProvider.model([LLMProvider.text_response("nil options done")])

    {:ok, nil_options_agent} =
      Agent.start_link(
        model: nil_model,
        llm_request_options: nil,
        load_project_instructions: false
      )

    assert {:ok, "nil options done"} = Condukt.run(nil_options_agent, "go", trace_context: context())
    assert_receive {LLMProvider, :request, ^nil_model_id, _context, nil_opts}
    assert header(headers(nil_opts), "traceparent")

    GenServer.stop(nil_options_agent)

    {headers_model, headers_model_id} = LLMProvider.model([LLMProvider.text_response("headers done")])

    {:ok, headers_agent} =
      Agent.start_link(
        model: headers_model,
        llm_request_options: [req_http_options: [headers: %{"x-label" => ["one", "two"]}]],
        load_project_instructions: false
      )

    assert {:ok, "headers done"} = Condukt.run(headers_agent, "go", trace_context: context())
    assert_receive {LLMProvider, :request, ^headers_model_id, _context, request_opts}
    assert [{"x-label", "one"}, {"x-label", "two"}] == Enum.filter(headers(request_opts), &(elem(&1, 0) == "x-label"))

    GenServer.stop(headers_agent)
  end

  test "captures the calling process context across the session task and gives retries distinct child spans" do
    retryable = %ReqLLM.Error.API.Request{status: 429, reason: "retry"}

    {model, model_id} =
      LLMProvider.model([{:error, retryable}, LLMProvider.text_response("done")])

    {:ok, agent} =
      Agent.start_link(
        id: "retry-session",
        model: model,
        retry: [max_attempts: 2, base_delay_ms: 0],
        load_project_instructions: false
      )

    TraceContext.put_current(context())
    on_exit(&TraceContext.clear_current/0)

    assert {:ok, "done"} = Condukt.run(agent, "go")

    assert_receive {LLMProvider, :request, ^model_id, _first_context, first_opts}
    assert_receive {LLMProvider, :request, ^model_id, _second_context, second_opts}

    refute header(headers(first_opts), "traceparent") == header(headers(second_opts), "traceparent")
    assert header(headers(first_opts), "baggage") =~ "condukt.session.id=retry-session"

    GenServer.stop(agent)
  end

  test "carries the run context through concurrent tool tasks" do
    test_pid = self()

    tool =
      Condukt.tool(
        name: "record_trace",
        description: "records the current trace context",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, tool_context ->
          send(test_pid, {:tool_trace_context, TraceContext.current(), tool_context.trace_context})
          {:ok, "recorded"}
        end
      )

    first = ToolCall.new("tool-1", "record_trace", JSON.encode!(%{}))
    second = ToolCall.new("tool-2", "record_trace", JSON.encode!(%{}))

    {model, _model_id} =
      LLMProvider.model([
        LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [first, second]}, :tool_calls),
        LLMProvider.text_response("done")
      ])

    {:ok, agent} = Agent.start_link(model: model, tools: [tool], load_project_instructions: false)

    assert {:ok, "done"} = Condukt.run(agent, "go", trace_context: context())

    assert_receive {:tool_trace_context, %TraceContext{} = task_context, %TraceContext{} = tool_context}
    assert_receive {:tool_trace_context, %TraceContext{} = second_task_context, %TraceContext{} = second_tool_context}

    assert task_context.trace_id == "0123456789abcdef0123456789abcdef"
    assert tool_context == task_context
    assert second_task_context == task_context
    assert second_tool_context == task_context

    GenServer.stop(agent)
  end

  test "carries trace context into child sessions while giving each session its own grouping id" do
    parent_call = ToolCall.new("delegate", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "inspect"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [parent_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, child_model_id} = LLMProvider.model([LLMProvider.text_response("child done")])

    {:ok, parent} =
      ParentAgent.start_link(
        id: "parent-session",
        model: parent_model,
        subagents: [researcher: {ChildAgent, model: child_model, load_project_instructions: false}],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate", trace_context: context())

    requests = receive_requests([parent_model_id, child_model_id, parent_model_id])
    parent_headers = requests |> Map.fetch!(parent_model_id) |> Enum.map(&headers/1)
    child_headers = requests |> Map.fetch!(child_model_id) |> List.first() |> headers()

    assert Enum.all?(parent_headers, &(header(&1, "baggage") =~ "condukt.session.id=parent-session"))
    refute header(child_headers, "baggage") =~ "condukt.session.id=parent-session"

    traceparents =
      parent_headers
      |> Enum.map(&header(&1, "traceparent"))
      |> Kernel.++([header(child_headers, "traceparent")])

    assert Enum.all?(traceparents, &String.starts_with?(&1, "00-0123456789abcdef0123456789abcdef-"))

    GenServer.stop(parent)
  end

  test "injects the same headers for streaming requests" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("unused")])

    {:ok, agent} =
      Agent.start_link(
        id: "stream-session",
        model: model,
        llm_request_options: [req_http_options: [headers: [{"x-tenant", "atlas"}]]],
        load_project_instructions: false
      )

    events = Condukt.stream(agent, "go", trace_context: context()) |> Enum.to_list()

    assert Enum.any?(events, &match?({:error, _}, &1))
    assert_receive {LLMProvider, :stream_request, ^model_id, _stream_context, opts}

    headers = headers(opts)
    assert {"x-tenant", "atlas"} in headers
    assert header(headers, "baggage") == "upstream=value,condukt.session.id=stream-session"
    assert String.starts_with?(header(headers, "traceparent"), "00-0123456789abcdef0123456789abcdef-")

    GenServer.stop(agent)
  end

  test "captures the calling process context when a different process consumes a stream" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("unused")])
    {:ok, agent} = Agent.start_link(id: "cross-process-stream", model: model, load_project_instructions: false)

    TraceContext.put_current(context())
    on_exit(&TraceContext.clear_current/0)

    stream = Condukt.stream(agent, "go")
    task = Task.async(fn -> Enum.to_list(stream) end)

    assert Enum.any?(Task.await(task), &match?({:error, _}, &1))
    assert_receive {LLMProvider, :stream_request, ^model_id, _stream_context, opts}
    assert String.starts_with?(header(headers(opts), "traceparent"), "00-0123456789abcdef0123456789abcdef-")

    GenServer.stop(agent)
  end

  defp context do
    TraceContext.new(
      trace_id: "0123456789abcdef0123456789abcdef",
      span_id: "0123456789abcdef",
      tracestate: "vendor=value",
      baggage: "upstream=value"
    )
  end

  defp headers(opts), do: opts |> Keyword.fetch!(:req_http_options) |> Keyword.fetch!(:headers)

  defp header(headers, name) do
    Enum.find_value(headers, fn {header_name, value} ->
      if String.downcase(header_name) == String.downcase(name), do: value
    end)
  end

  defp receive_requests(model_ids) do
    Enum.reduce(model_ids, %{}, fn _model_id, requests ->
      receive do
        {LLMProvider, :request, model_id, _context, opts} -> Map.update(requests, model_id, [opts], &[opts | &1])
      after
        1_000 -> flunk("expected a recorded ReqLLM request")
      end
    end)
  end
end
