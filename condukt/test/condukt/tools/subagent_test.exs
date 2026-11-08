defmodule Condukt.Tools.SubagentTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider
  alias Condukt.Tool
  alias Condukt.Tools.Subagent
  alias ReqLLM.Message
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
