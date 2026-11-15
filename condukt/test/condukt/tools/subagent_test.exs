defmodule Condukt.Tools.SubagentTest do
  use ExUnit.Case, async: true

  alias Condukt.Session.View
  alias Condukt.Test.LLMProvider
  alias Condukt.Tool
  alias Condukt.Tools.BackgroundSubagent
  alias Condukt.Tools.Subagent
  alias ReqLLM.Message
  alias ReqLLM.StreamChunk
  alias ReqLLM.ToolCall

  defmodule ParentAgent do
    use Condukt

    @impl true
    def tools, do: []
  end

  defmodule ChildAgent do
    use Condukt
  end

  defmodule CrashAgent do
    use Condukt

    @impl true
    def init(_opts), do: {:stop, :boom}
  end

  # Sessions started under a supervisor do not inherit `$callers`, so each one
  # allows the test's ReqLLM stub itself.
  defmodule StreamAgent do
    use Condukt

    @impl true
    def init(opts) do
      if test_pid = opts[:test_pid], do: Mimic.allow(ReqLLM, test_pid, self())
      {:ok, opts}
    end
  end

  defmodule EchoRuntime do
    def run(_prompt, _context, _opts), do: {:ok, "echo"}
  end

  defmodule ChildNotifier do
    @behaviour Condukt.Notifier

    @impl true
    def publish(_session_id, event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:child_notified, event})
      :ok
    end
  end

  defmodule RecordingNotifier do
    @behaviour Condukt.Notifier

    @impl true
    def publish(_session_id, event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:notified, event})
      :ok
    end
  end

  test "builds a role enum from registered subagents" do
    input_schema = %{
      type: "object",
      properties: %{
        path: %{type: "string"},
        detail: %{type: "string"}
      },
      required: ["path"]
    }

    optional_input_schema = %{
      type: "object",
      properties: %{detail: %{type: "string"}}
    }

    spec =
      Tool.to_spec(
        {Subagent,
         subagents: [
           researcher: {ChildAgent, input: input_schema},
           coder: {ChildAgent, model: "test", input: optional_input_schema},
           analyst: [model: "test", input: optional_input_schema]
         ]}
      )

    assert spec.name == "subagent"

    [researcher_schema, coder_schema, analyst_schema] = spec.parameters.oneOf

    assert researcher_schema.properties.role.enum == ["researcher"]
    assert researcher_schema.properties.input == input_schema
    assert researcher_schema.required == ["role", "task", "input"]

    assert coder_schema.properties.role.enum == ["coder"]
    assert coder_schema.properties.input == optional_input_schema
    assert coder_schema.required == ["role", "task"]

    assert analyst_schema.properties.role.enum == ["analyst"]
    assert analyst_schema.properties.input == optional_input_schema
    assert analyst_schema.required == ["role", "task"]
  end

  test "delegates to a child session and returns its final answer as the tool result" do
    tool_call = ToolCall.new("call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "write notes"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, child_model_id} = LLMProvider.model(LLMProvider.text_response("field notes"))

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {LLMProvider, :request, ^parent_model_id, _context, parent_opts}
    subagent_tool = Enum.find(parent_opts[:tools], &(&1.name == "subagent"))

    assert get_in(subagent_tool.parameter_schema, ["oneOf", Access.at(0), "properties", "role", "enum"]) == [
             "researcher"
           ]

    assert_receive {LLMProvider, :request, ^child_model_id, child_context, _child_opts}
    assert Enum.any?(child_context.messages, &message_text?(&1, "write notes"))

    assert_receive {LLMProvider, :request, ^parent_model_id, _context, _parent_opts}

    assert Enum.any?(Condukt.history(parent), fn
             %Condukt.Message{role: :tool_result, content: "field notes"} -> true
             _message -> false
           end)

    assert :sys.get_state(parent).subagent_supervisor |> DynamicSupervisor.which_children() == []

    GenServer.stop(parent)
  end

  test "inherits parent LLM configuration for child sessions" do
    tool_call = ToolCall.new("call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "write notes"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("field notes"),
        LLMProvider.text_response("parent done")
      ])

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        api_key: "test-key",
        base_url: "https://llm.example.com/v1",
        thinking_level: :low,
        subagents: [
          researcher: {ChildAgent, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {LLMProvider, :request, ^parent_model_id, _parent_context, _parent_opts}
    assert_receive {LLMProvider, :request, ^parent_model_id, child_context, child_opts}

    assert Enum.any?(child_context.messages, &message_text?(&1, "write notes"))
    assert child_opts[:api_key] == "test-key"
    assert child_opts[:base_url] == "https://llm.example.com/v1"
    assert child_opts[:reasoning_effort] == :low

    assert_receive {LLMProvider, :request, ^parent_model_id, _context, _parent_opts}

    GenServer.stop(parent)
  end

  test "validates structured input and passes optional fields as optional" do
    input_schema = %{
      type: "object",
      properties: %{
        path: %{type: "string"},
        detail: %{type: "string"}
      },
      required: ["path"]
    }

    tool_call =
      ToolCall.new(
        "call_1",
        "subagent",
        JSON.encode!(%{"role" => "researcher", "task" => "inspect", "input" => %{"path" => "README.md"}})
      )

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, child_model_id} = LLMProvider.model(LLMProvider.text_response("checked"))

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, input: input_schema, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {LLMProvider, :request, ^child_model_id, child_context, _child_opts}
    assert Enum.any?(child_context.messages, &message_contains?(&1, ~s("path":"README.md")))
    refute Enum.any?(child_context.messages, &message_contains?(&1, "detail"))

    GenServer.stop(parent)
  end

  test "returns an error when structured input does not match the role schema" do
    input_schema = %{
      type: "object",
      properties: %{path: %{type: "string"}},
      required: ["path"]
    }

    assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
             Tool.execute(
               {Subagent, subagents: [researcher: {ChildAgent, input: input_schema}]},
               %{"role" => "researcher", "task" => "inspect", "input" => %{}},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: self()}
             )
  end

  test "returns validated structured output from a child session" do
    output_schema = %{
      type: "object",
      properties: %{
        summary: %{type: "string"},
        follow_up: %{type: "string"}
      },
      required: ["summary"]
    }

    child_submit = ToolCall.new("child_call_1", "submit_result", JSON.encode!(%{"summary" => "field notes"}))

    parent_call =
      ToolCall.new("parent_call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "summarize"}))

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [parent_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, _child_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [child_submit]}, :tool_calls),
        LLMProvider.text_response("submitted")
      ])

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, output: output_schema, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert Enum.any?(Condukt.history(parent), fn
             %Condukt.Message{role: :tool_result, content: %{summary: "field notes"}} -> true
             _message -> false
           end)

    GenServer.stop(parent)
  end

  test "emits telemetry around structured delegation" do
    handler_id = "subagent-telemetry-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:condukt, :subagent, :start],
        [:condukt, :subagent, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:subagent_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    input_schema = %{
      type: "object",
      properties: %{path: %{type: "string"}},
      required: ["path"]
    }

    output_schema = %{
      type: "object",
      properties: %{summary: %{type: "string"}},
      required: ["summary"]
    }

    child_submit = ToolCall.new("child_call_1", "submit_result", JSON.encode!(%{"summary" => "field notes"}))

    parent_call =
      ToolCall.new(
        "parent_call_1",
        "subagent",
        JSON.encode!(%{
          "role" => "researcher",
          "task" => "summarize",
          "input" => %{"path" => "README.md"}
        })
      )

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [parent_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, _child_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [child_submit]}, :tool_calls),
        LLMProvider.text_response("submitted")
      ])

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher:
            {ChildAgent,
             model: child_model, input: input_schema, output: output_schema, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :start], %{system_time: _},
                    %{
                      agent: ParentAgent,
                      role: :researcher,
                      child_agent: ChildAgent,
                      input?: true,
                      output?: true
                    }}

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :stop], %{duration: _},
                    %{
                      agent: ParentAgent,
                      role: :researcher,
                      child_agent: ChildAgent,
                      input?: true,
                      output?: true,
                      status: :ok
                    }}

    GenServer.stop(parent)
  end

  test "subagent telemetry carries parent and child session ids" do
    handler_id = "subagent-session-ids-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [[:condukt, :subagent, :start], [:condukt, :subagent, :stop]],
      fn event, _measurements, metadata, _config ->
        send(test_pid, {:subagent_telemetry, event, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    parent_call = ToolCall.new("parent_call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "go"}))

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [parent_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, _child_model_id} =
      LLMProvider.model([LLMProvider.text_response("child done")])

    parent_id = "11111111-2222-7333-8444-555555555555"

    {:ok, parent} =
      ParentAgent.start_link(
        id: parent_id,
        model: parent_model,
        subagents: [researcher: {ChildAgent, model: child_model, load_project_instructions: false}],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :start], %{parent_session_id: ^parent_id}}

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :stop],
                    %{parent_session_id: ^parent_id, session_id: child_session_id, status: :ok}}

    assert is_binary(child_session_id)
    assert child_session_id != parent_id

    GenServer.stop(parent)
  end

  test "emits telemetry when structured input validation fails" do
    handler_id = "subagent-invalid-input-telemetry-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:condukt, :subagent, :start],
        [:condukt, :subagent, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:subagent_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    input_schema = %{
      type: "object",
      properties: %{path: %{type: "string"}},
      required: ["path"]
    }

    assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
             Tool.execute(
               {Subagent, subagents: [researcher: {ChildAgent, input: input_schema}]},
               %{"role" => "researcher", "task" => "inspect", "input" => %{}},
               %{agent: ParentAgent, sandbox: nil, cwd: ".", subagent_supervisor: self()}
             )

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :start], %{system_time: _},
                    %{
                      agent: ParentAgent,
                      role: :researcher,
                      child_agent: ChildAgent,
                      input?: true,
                      output?: false
                    }}

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :stop], %{duration: _},
                    %{
                      agent: ParentAgent,
                      role: :researcher,
                      child_agent: ChildAgent,
                      input?: true,
                      output?: false,
                      status: :error,
                      error: :invalid_input
                    }}
  end

  test "subagent telemetry emits an exception lifecycle when delegation raises" do
    handler_id = "subagent-exception-telemetry-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [[:condukt, :subagent, :start], [:condukt, :subagent, :exception]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:subagent_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, _} =
             Tool.execute(
               {Subagent, subagents: [researcher: ChildAgent]},
               %{"role" => "researcher", "task" => "private task"},
               %{agent: ParentAgent, subagent_supervisor: self()}
             )

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :start], %{system_time: _}, _metadata}

    assert_receive {:subagent_telemetry, [:condukt, :subagent, :exception], %{duration: _}, metadata}
    assert %{kind: :error, reason: _reason, stacktrace: stacktrace} = metadata
    assert is_list(stacktrace)
  end

  test "returns an error for an unknown role" do
    assert {:error, "no sub-agent registered as writer"} =
             Tool.execute(
               {Subagent, subagents: [researcher: ChildAgent]},
               %{"role" => "writer", "task" => "draft"},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: self()}
             )
  end

  test "returns an error when the child cannot start" do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    assert {:error, :boom} =
             Tool.execute(
               {Subagent, subagents: [crasher: CrashAgent]},
               %{"role" => "crasher", "task" => "crash"},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: supervisor}
             )

    Supervisor.stop(supervisor)
  end

  test "stopping the parent session stops the subagent supervisor and children" do
    {:ok, parent} =
      ParentAgent.start_link(
        subagents: [worker: ChildAgent],
        load_project_instructions: false
      )

    supervisor = :sys.get_state(parent).subagent_supervisor

    {:ok, child} =
      DynamicSupervisor.start_child(supervisor, %{
        id: {__MODULE__, :manual_child},
        start: {Condukt.Session, :start_link, [ChildAgent, [load_project_instructions: false]]},
        restart: :temporary,
        type: :worker
      })

    supervisor_ref = Process.monitor(supervisor)
    child_ref = Process.monitor(child)

    GenServer.stop(parent)

    assert_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}
    assert_receive {:DOWN, ^child_ref, :process, ^child, _reason}
  end

  test "aborting the parent turn aborts a running foreground child" do
    test_pid = self()
    tool_call = ToolCall.new("call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "write notes"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("must not run")
      ])

    {child_model, _child_model_id} =
      LLMProvider.model([
        fn ->
          send(test_pid, {:child_inference, self()})
          receive do: (:continue -> LLMProvider.text_response("late notes"))
        end
      ])

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [researcher: {ChildAgent, model: child_model, load_project_instructions: false}],
        load_project_instructions: false
      )

    task = Task.async(fn -> Condukt.run(parent, "delegate") end)
    assert_receive {:child_inference, inference}, 1_000

    # The child's turn runs under the child session, which runs under the
    # supervisor the call started: [child turns, child, call's supervisor | _].
    {:dictionary, dictionary} = Process.info(inference, :dictionary)
    [_child_turns, child, call_supervisor | _] = Keyword.fetch!(dictionary, :"$ancestors")
    assert %Condukt.Session{} = :sys.get_state(child)
    refs = Map.new([inference, child, call_supervisor], &{&1, Process.monitor(&1)})
    worker_ref = Process.monitor(:sys.get_state(parent).turn.worker)

    assert :ok = Condukt.abort(parent)
    assert Task.await(task) == {:error, :aborted}
    # The child's inference is still blocked, so only the abort can end it.
    for {pid, ref} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, :shutdown}, 1_000)
    assert_receive {:DOWN, ^worker_ref, :process, _worker, :shutdown}, 1_000
    assert_received {LLMProvider, :request, ^parent_model_id, _context, _opts}
    refute_receive {LLMProvider, :request, ^parent_model_id, _context, _opts}, 20

    GenServer.stop(parent)
  end

  test "streams a foreground child's events into the parent stream, tagged with the call" do
    {parent_model, parent_model_id} = LLMProvider.model([])
    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      parent_model_id => [
        stream_response(
          [
            StreamChunk.tool_call("subagent", %{"role" => "researcher", "task" => "write notes"}, %{
              id: "call_1",
              index: 0
            })
          ],
          :tool_calls
        ),
        stream_response([StreamChunk.text("parent done")])
      ],
      child_model_id => [stream_response([StreamChunk.text("field "), StreamChunk.text("notes")])]
    })

    {:ok, parent} =
      StreamAgent.start_link(
        model: parent_model,
        test_pid: self(),
        notifier: {RecordingNotifier, test_pid: self()},
        subagents: [researcher: {StreamAgent, model: child_model, test_pid: self(), load_project_instructions: false}],
        load_project_instructions: false
      )

    events = Condukt.stream(parent, "delegate") |> Enum.to_list()

    child_events = for {:subagent, "call_1", event} <- events, do: event
    assert [:agent_start | _] = child_events
    assert {:text, "field "} in child_events
    assert {:text, "notes"} in child_events
    assert List.last(child_events) == :done

    index = fn event -> Enum.find_index(events, &(&1 == event)) end

    assert index.({:tool_call, "subagent", "call_1", %{"role" => "researcher", "task" => "write notes"}}) <
             index.({:subagent, "call_1", :agent_start})

    assert index.({:subagent, "call_1", :done}) < index.({:tool_result, "call_1", "field notes"})
    assert_received {:notified, {:subagent, "call_1", {:text, "notes"}}}

    assert :sys.get_state(parent).subagent_supervisor |> DynamicSupervisor.which_children() == []

    GenServer.stop(parent)
  end

  test "a background sub-agent outlives the parent turn and reports its answer as a follow-up" do
    test_pid = self()
    spawn_call = ToolCall.new("call_1", "background_subagent", spawn_args("read the book"))
    wait_call = ToolCall.new("call_2", "background_subagent", JSON.encode!(%{"action" => "wait", "name" => "reader"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [spawn_call]}, :tool_calls),
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [wait_call]}, :tool_calls),
        LLMProvider.text_response("must not run")
      ])

    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      parent_model_id => [stream_response([StreamChunk.text("noted")])],
      child_model_id => [stream_response(blocking_chunks(test_pid, :reading, "a whale"))]
    })

    {:ok, parent} =
      StreamAgent.start_link(
        model: parent_model,
        test_pid: test_pid,
        notifier: {RecordingNotifier, test_pid: test_pid},
        subagents: [reader: background_role(child_model, notifier: {ChildNotifier, test_pid: test_pid})],
        load_project_instructions: false
      )

    task = Task.async(fn -> Condukt.run(parent, "start a reader") end)
    assert_receive {:child_inference, :reading, inference}, 1_000
    on_exit(fn -> send(inference, :continue) end)
    # The `wait` call is waiting.
    {BackgroundSubagent, tool_opts} = Enum.find(:sys.get_state(parent).tools, &match?({BackgroundSubagent, _}, &1))
    eventually(fn -> :sys.get_state(tool_opts[:manager]).children["reader"].waiters != %{} end)

    assert :ok = Condukt.abort(parent)
    assert Task.await(task) == {:error, :aborted}

    child = background_child(parent)
    assert :sys.get_state(child).turn.streaming
    # Recorded as the parent's child, by the parent's session id.
    assert Condukt.Sessions.children(Condukt.Session.id(parent)) == [{Condukt.Session.id(child), child}]

    send(inference, :continue)

    history =
      await_history(parent, fn history ->
        Enum.map(history, &{&1.role, Condukt.Message.text(&1)}) ==
          [{:user, "[subagent reader answered] a whale"}, {:assistant, "noted"}]
      end)

    assert length(history) == 2
    assert_received {:notified, {:subagent, "call_1", {:text, "a whale"}}}
    # The notifier the role configured still sees the child's own events.
    assert_received {:child_notified, {:text, "a whale"}}

    GenServer.stop(parent)
  end

  test "background sub-agents can be listed, stopped, messaged, and waited for" do
    test_pid = self()
    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      child_model_id => [
        stream_response(blocking_chunks(test_pid, :chapters, "Chapter 1")),
        stream_response(blocking_chunks(test_pid, :whale, "Moby Dick"))
      ]
    })

    {:ok, parent} =
      StreamAgent.start_link(
        test_pid: test_pid,
        notifier: {RecordingNotifier, test_pid: test_pid},
        subagents: [reader: background_role(child_model)],
        load_project_instructions: false
      )

    state = :sys.get_state(parent)
    refute Enum.any?(state.tools, &match?({Subagent, _opts}, &1))
    {BackgroundSubagent, tool_opts} = tool = Enum.find(state.tools, &match?({BackgroundSubagent, _opts}, &1))
    context = %{agent: parent, sandbox: state.sandbox, cwd: state.cwd, tool_call_id: "call_1"}
    call = fn args -> Tool.execute(tool, args, context) end

    assert {:ok, %{name: "reader", status: "working"}} = call.(JSON.decode!(spawn_args("summarize every chapter")))
    assert {:error, "reader already exists; use send"} = call.(JSON.decode!(spawn_args("again")))

    # Host code reaches the child by parent and name, like any session.
    reader = BackgroundSubagent.whereis(parent, "reader")
    assert reader == background_child(parent)
    assert {:ok, [%{session_id: session_id}]} = call.(%{"action" => "list"})
    assert Condukt.Session.id(reader) == session_id
    assert BackgroundSubagent.whereis(parent, "writer") == nil
    assert_receive {:child_inference, :chapters, chapters}, 1_000
    on_exit(fn -> Process.exit(chapters, :kill) end)

    assert {:ok, [%{name: "reader", role: :reader, status: "working"}]} = call.(%{"action" => "list"})
    assert {:ok, _view} = call.(%{"action" => "stop", "name" => "reader"})
    assert {:ok, [%{status: "idle"}]} = call.(%{"action" => "list"})

    assert {:ok, %{status: "working"}} =
             call.(%{"action" => "send", "name" => "reader", "message" => "What is the whale called?"})

    assert_receive {:child_inference, :whale, whale}, 1_000
    waiter = Task.async(fn -> call.(%{"action" => "wait", "name" => "reader"}) end)
    eventually(fn -> :sys.get_state(tool_opts[:manager]).children["reader"].waiters != %{} end)
    send(whale, :continue)

    assert {:ok, %{status: "idle", answer: "Moby Dick"}} = Task.await(waiter)
    assert {:ok, %{status: "idle", answer: "Moby Dick"}} = call.(%{"action" => "wait", "name" => "reader"})
    assert {:error, "no background sub-agent named writer"} = call.(%{"action" => "stop", "name" => "writer"})

    # The answer went to the caller that waited, so the parent gets no report.
    refute_receive {:notified, :agent_start}, 50
    assert Condukt.history(parent) == []

    GenServer.stop(parent)
  end

  # A viewer of the parent sees each background sub-agent by name, its status,
  # and what its turn did, from changes that fold into the parent's own view.
  test "the parent's view shows background sub-agents and their turns" do
    test_pid = self()
    {parent_model, parent_model_id} = LLMProvider.model([])
    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      parent_model_id => [stream_response([StreamChunk.text("noted")])],
      child_model_id => [
        stream_response(blocking_chunks(test_pid, :chapters, "Chapter 1")),
        stream_response([StreamChunk.text("Chapter 2")])
      ]
    })

    {:ok, parent} =
      StreamAgent.start_link(
        model: parent_model,
        test_pid: test_pid,
        subagents: [reader: background_role(child_model)],
        load_project_instructions: false
      )

    watched = Condukt.watch(parent)
    assert watched.background == %{}

    state = :sys.get_state(parent)
    tool = Enum.find(state.tools, &match?({BackgroundSubagent, _opts}, &1))
    context = %{agent: parent, sandbox: state.sandbox, cwd: state.cwd, tool_call_id: "call_1"}
    call = fn args -> Tool.execute(tool, args, context) end

    assert {:ok, %{status: "working"}} = call.(JSON.decode!(spawn_args("summarize every chapter")))
    assert_receive {:child_inference, :chapters, chapters}, 1_000

    assert %{"reader" => %{role: :reader, call_id: "call_1", status: :working, session_id: session_id}} =
             Condukt.view(parent).background

    assert is_binary(session_id)

    # The wait claims the answer, so no report starts a parent turn.
    waiter = Task.async(fn -> call.(%{"action" => "wait", "name" => "reader"}) end)
    send(chapters, :continue)
    assert {:ok, %{answer: "Chapter 1"}} = Task.await(waiter)

    eventually(fn -> Condukt.view(parent).background["reader"].status == :idle end)

    assert [%{type: :user, message: %{content: "summarize every chapter"}}, %{type: :assistant, text: "Chapter 1"}] =
             Condukt.view(parent).background["reader"].run.items

    # A later turn replaces the run, starting from the message it was sent.
    assert {:ok, _view} = call.(%{"action" => "send", "name" => "reader", "message" => "And chapter 2?"})
    assert {:ok, %{answer: "Chapter 2"}} = call.(%{"action" => "wait", "name" => "reader"})
    eventually(fn -> Condukt.view(parent).background["reader"].status == :idle end)
    final = Condukt.view(parent)

    assert [%{type: :user, message: %{content: "And chapter 2?"}}, %{type: :assistant, text: "Chapter 2"}] =
             final.background["reader"].run.items

    folded =
      Enum.reduce((watched.seq + 1)..final.seq//1, watched, fn seq, view ->
        assert_receive {:condukt_change, _id, epoch, ^seq, change}
        {:ok, view} = View.advance(view, epoch, seq, change)
        view
      end)

    assert folded == final

    child = background_child(parent)
    monitor = Process.monitor(child)
    Process.exit(child, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^child, :killed}
    eventually(fn -> Condukt.view(parent).background == %{} end)

    # The crash is reported to the parent, which answers it in a turn of its own.
    await_history(parent, &match?([_report, %{role: :assistant}], &1))

    GenServer.stop(parent)
  end

  test "an answer a wait claims is not also reported to the parent" do
    test_pid = self()
    spawn_call = ToolCall.new("call_1", "background_subagent", spawn_args("read the book"))
    wait_call = ToolCall.new("call_2", "background_subagent", JSON.encode!(%{"action" => "wait", "name" => "reader"}))

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [spawn_call]}, :tool_calls),
        fn ->
          send(test_pid, {:parent_inference, self()})

          receive do: (:continue ->
                         LLMProvider.response(
                           %Message{role: :assistant, content: [], tool_calls: [wait_call]},
                           :tool_calls
                         ))
        end,
        LLMProvider.text_response("final")
      ])

    {child_model, child_model_id} = LLMProvider.model([])
    stub_streams(%{child_model_id => [stream_response([StreamChunk.text("a whale")])]})

    {:ok, parent} =
      StreamAgent.start_link(
        model: parent_model,
        test_pid: test_pid,
        notifier: {RecordingNotifier, test_pid: test_pid},
        subagents: [reader: background_role(child_model)],
        load_project_instructions: false
      )

    task = Task.async(fn -> Condukt.run(parent, "start a reader") end)
    assert_receive {:parent_inference, inference}, 1_000
    # The child answers before the parent asks to wait, so its report is queued.
    assert_receive {:notified, {:subagent, "call_1", :done}}, 1_000
    eventually(fn -> :sys.get_state(parent).turn.reports != [] end)
    send(inference, :continue)

    assert Task.await(task) == {:ok, "final"}

    assert Enum.any?(Condukt.history(parent), fn
             %Condukt.Message{role: :tool_result, content: %{answer: "a whale"}} -> true
             _message -> false
           end)

    state = :sys.get_state(parent)
    assert state.turn.reports == []
    refute state.turn.streaming
    refute Enum.any?(Condukt.history(parent), &(&1.role == :user and &1.content =~ "[subagent"))

    GenServer.stop(parent)
  end

  test "a report queued during a parent turn survives aborting that turn" do
    test_pid = self()
    spawn_call = ToolCall.new("call_1", "background_subagent", spawn_args("read the book"))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [spawn_call]}, :tool_calls),
        fn ->
          send(test_pid, {:parent_inference, self()})
          receive do: (:continue -> LLMProvider.text_response("must not land"))
        end
      ])

    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      parent_model_id => [stream_response([StreamChunk.text("noted")])],
      child_model_id => [stream_response([StreamChunk.text("a whale")])]
    })

    {:ok, parent} =
      StreamAgent.start_link(
        model: parent_model,
        test_pid: test_pid,
        notifier: {RecordingNotifier, test_pid: test_pid},
        subagents: [reader: background_role(child_model)],
        load_project_instructions: false
      )

    task = Task.async(fn -> Condukt.run(parent, "start a reader") end)
    assert_receive {:parent_inference, inference}, 1_000
    on_exit(fn -> Process.exit(inference, :kill) end)
    eventually(fn -> :sys.get_state(parent).turn.reports != [] end)

    assert :ok = Condukt.abort(parent)
    assert Task.await(task) == {:error, :aborted}

    await_history(parent, fn history ->
      Enum.map(history, &{&1.role, Condukt.Message.text(&1)}) ==
        [{:user, "[subagent reader answered] a whale"}, {:assistant, "noted"}]
    end)

    GenServer.stop(parent)
  end

  test "spawning a background role that cannot take queued input fails instead of hanging" do
    {:ok, parent} =
      StreamAgent.start_link(
        subagents: [
          reader: {StreamAgent, runtime: EchoRuntime, background: true, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    state = :sys.get_state(parent)
    tool = Enum.find(state.tools, &match?({BackgroundSubagent, _opts}, &1))
    context = %{agent: parent, sandbox: state.sandbox, cwd: state.cwd, tool_call_id: "call_1"}

    assert {:error, {:background_subagent_requires_native_runtime, StreamAgent}} =
             Tool.execute(tool, JSON.decode!(spawn_args("read")), context)

    assert {:ok, []} = Tool.execute(tool, %{"action" => "list"}, context)
    # Only the manager is left under the supervisor.
    assert [_manager] = DynamicSupervisor.which_children(state.subagent_supervisor)

    GenServer.stop(parent)
  end

  defp spawn_args(message) do
    JSON.encode!(%{"action" => "spawn", "name" => "reader", "role" => "reader", "message" => message})
  end

  defp background_role(model, opts \\ []) do
    {StreamAgent, [model: model, test_pid: self(), background: true, load_project_instructions: false] ++ opts}
  end

  defp background_child(parent) do
    parent
    |> :sys.get_state()
    |> Map.fetch!(:subagent_supervisor)
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.find(&match?(%Condukt.Session{}, :sys.get_state(&1)))
  end

  defp blocking_chunks(test_pid, tag, text) do
    Stream.map([text], fn text ->
      send(test_pid, {:child_inference, tag, self()})
      receive do: (:continue -> StreamChunk.text(text))
    end)
  end

  defp stub_streams(scripts) do
    scripts = start_supervised!({Agent, fn -> scripts end}, id: make_ref())

    Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
      response =
        Agent.get_and_update(scripts, fn scripts ->
          [response | rest] = Map.fetch!(scripts, model.id)
          {response, Map.put(scripts, model.id, rest)}
        end)

      {:ok, %{response | model: ReqLLM.model!(model), context: context}}
    end)
  end

  defp stream_response(chunks, finish_reason \\ :stop) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: finish_reason} end},
        id: make_ref()
      )

    %ReqLLM.StreamResponse{stream: chunks, metadata_handle: metadata, cancel: fn -> :ok end, model: nil, context: nil}
  end

  defp eventually(check, attempts \\ 200) do
    cond do
      check.() -> :ok
      attempts == 0 -> flunk("condition never held")
      true -> Process.sleep(5) && eventually(check, attempts - 1)
    end
  end

  defp await_history(pid, predicate) do
    eventually(fn -> predicate.(Condukt.history(pid)) end)
    Condukt.history(pid)
  end

  defp message_text?(%Message{content: content}, text) when is_list(content) do
    Enum.any?(content, fn
      %{text: ^text} -> true
      _part -> false
    end)
  end

  defp message_text?(%Message{content: text}, text) when is_binary(text), do: true
  defp message_text?(_message, _text), do: false

  defp message_contains?(%Message{content: content}, text) when is_list(content) do
    Enum.any?(content, fn
      %{text: part_text} when is_binary(part_text) -> String.contains?(part_text, text)
      _part -> false
    end)
  end

  defp message_contains?(%Message{content: content}, text) when is_binary(content), do: String.contains?(content, text)
  defp message_contains?(_message, _text), do: false
end
