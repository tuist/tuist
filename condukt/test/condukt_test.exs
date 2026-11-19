defmodule ConduktTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  defmodule DummyAgent do
    use Condukt
  end

  defmodule ModuleNameTool do
    use Condukt.Tool

    @impl true
    def name, do: "module_name"

    @impl true
    def description, do: "Returns the session agent module."

    @impl true
    def parameters, do: %{type: "object", properties: %{}}

    @impl true
    def call(_args, context), do: {:ok, inspect(context.agent_module)}
  end

  defmodule ModuleAgent do
    use Condukt

    @impl true
    def system_prompt, do: "module one-shot prompt"

    @impl true
    def tools, do: [ModuleNameTool]
  end

  defmodule PlainModuleAgent do
    @behaviour Condukt

    @impl true
    def runtime, do: Condukt.AgentRuntimes.Native

    @impl true
    def system_prompt, do: "plain module one-shot prompt"

    @impl true
    def tools, do: []

    @impl true
    def subagents, do: []

    @impl true
    def model, do: "test:model"

    @impl true
    def thinking_level, do: :medium

    @impl true
    def sandbox, do: nil

    @impl true
    def secrets, do: nil

    def mcp_servers, do: []

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "delegates prompt-first calls to anonymous runs" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("from anonymous"))

    assert {:ok, "from anonymous"} = Condukt.run("hi", model: model)
  end

  test "runs module-defined agents as transient one-shot sessions" do
    {model, model_id} = LLMProvider.model(LLMProvider.text_response("from module"))

    assert {:ok, "from module"} =
             Condukt.run(ModuleAgent, "hi",
               model: model,
               load_project_instructions: false
             )

    assert_receive {LLMProvider, :request, ^model_id, context, opts}
    assert inspect(context) =~ "module one-shot prompt"
    assert Enum.any?(opts[:tools], &(&1.name == "module_name"))
  end

  test "runs plain Condukt behaviour modules without operation metadata as transient one-shot sessions" do
    {model, model_id} = LLMProvider.model(LLMProvider.text_response("from plain module"))

    assert {:ok, "from plain module"} =
             Condukt.run(PlainModuleAgent, "hi",
               model: model,
               load_project_instructions: false
             )

    assert_receive {LLMProvider, :request, ^model_id, context, _opts}
    assert inspect(context) =~ "plain module one-shot prompt"
  end

  test "module-defined one-shot runs support structured output with module tools" do
    submitted = %{"module_seen" => inspect(ModuleAgent)}
    module_call = ToolCall.new("call_1", "module_name", JSON.encode!(%{}))
    submit_call = ToolCall.new("call_2", "submit_result", JSON.encode!(submitted))

    {model, model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [module_call]}, :tool_calls),
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [submit_call]}, :tool_calls),
        LLMProvider.text_response("Done.")
      ])

    assert {:ok, %{module_seen: module_seen}} =
             Condukt.run(ModuleAgent, "Return the module seen by the tool.",
               model: model,
               load_project_instructions: false,
               output: %{
                 type: "object",
                 properties: %{module_seen: %{type: "string"}},
                 required: ["module_seen"]
               }
             )

    assert module_seen == inspect(ModuleAgent)

    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    assert Enum.any?(opts[:tools], &(&1.name == "module_name"))
    assert Enum.any?(opts[:tools], &(&1.name == "submit_result"))
  end

  test "delegates pid-first calls to Condukt.Session" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("from session"))
    {:ok, pid} = start_supervised({DummyAgent, [model: model, load_project_instructions: false]})

    assert {:ok, "from session"} = Condukt.run(pid, "hi")
  end

  test "delegates non-module atom names to Condukt.Session" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("from named session"))

    {:ok, _pid} =
      start_supervised({DummyAgent, [name: :named_dummy_agent, model: model, load_project_instructions: false]})

    assert {:ok, "from named session"} = Condukt.run(:named_dummy_agent, "hi")
  end
end
