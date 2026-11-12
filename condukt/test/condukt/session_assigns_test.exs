defmodule Condukt.SessionAssignsTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  defmodule ScriptAgent do
    use Condukt

    @impl true
    def tools, do: []
  end

  test "tool returning assigns merges them into session state and later tools see them" do
    test_pid = self()

    write_tool =
      Condukt.tool(
        name: "remember",
        description: "stores an assign",
        parameters: %{
          type: "object",
          properties: %{value: %{type: "integer"}},
          required: ["value"]
        },
        call: fn %{"value" => value}, ctx ->
          send(test_pid, {:write_seen_assigns, ctx.assigns})
          {:ok, "stored", %{remembered: value}}
        end
      )

    read_tool =
      Condukt.tool(
        name: "recall",
        description: "reads an assign",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, ctx ->
          send(test_pid, {:read_seen_assigns, ctx.assigns})
          {:ok, "ok"}
        end
      )

    write_call = ToolCall.new("call_1", "remember", JSON.encode!(%{"value" => 42}))
    read_call = ToolCall.new("call_2", "recall", JSON.encode!(%{}))

    {model, model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [write_call]}, :tool_calls),
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [read_call]}, :tool_calls),
        LLMProvider.text_response("done")
      ])

    {:ok, agent} =
      ScriptAgent.start_link(
        model: model,
        tools: [write_tool, read_tool],
        load_project_instructions: false
      )

    assert {:ok, "done"} = Condukt.run(agent, "go")

    assert_receive {LLMProvider, :request, ^model_id, _, _}
    assert_receive {:write_seen_assigns, %{}}
    assert_receive {:read_seen_assigns, %{remembered: 42}}

    assert :sys.get_state(agent).assigns == %{remembered: 42}

    GenServer.stop(agent)
  end

  test "tool returning {:ok, term} only does not affect assigns" do
    test_pid = self()

    plain_tool =
      Condukt.tool(
        name: "plain",
        description: "returns nothing extra",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, ctx ->
          send(test_pid, {:plain_seen_assigns, ctx.assigns})
          {:ok, "fine"}
        end
      )

    plain_call = ToolCall.new("call_1", "plain", JSON.encode!(%{}))

    {model, _model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [plain_call]}, :tool_calls),
        LLMProvider.text_response("done")
      ])

    {:ok, agent} =
      ScriptAgent.start_link(
        model: model,
        tools: [plain_tool],
        assigns: %{seeded: true},
        load_project_instructions: false
      )

    assert {:ok, "done"} = Condukt.run(agent, "go")
    assert_receive {:plain_seen_assigns, %{seeded: true}}

    assert :sys.get_state(agent).assigns == %{seeded: true}

    GenServer.stop(agent)
  end

  test "assigns persist across multiple Condukt.run calls on the same session" do
    test_pid = self()

    bump_tool =
      Condukt.tool(
        name: "bump",
        description: "bumps a counter",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, ctx ->
          previous = Map.get(ctx.assigns, :counter, 0)
          send(test_pid, {:bump_seen, previous})
          {:ok, "bumped", %{counter: previous + 1}}
        end
      )

    bump_call_1 = ToolCall.new("call_1", "bump", JSON.encode!(%{}))
    bump_call_2 = ToolCall.new("call_2", "bump", JSON.encode!(%{}))

    {model, _model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [bump_call_1]}, :tool_calls),
        LLMProvider.text_response("first"),
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [bump_call_2]}, :tool_calls),
        LLMProvider.text_response("second")
      ])

    {:ok, agent} =
      ScriptAgent.start_link(
        model: model,
        tools: [bump_tool],
        load_project_instructions: false
      )

    assert {:ok, "first"} = Condukt.run(agent, "go")
    assert_receive {:bump_seen, 0}

    assert {:ok, "second"} = Condukt.run(agent, "again")
    assert_receive {:bump_seen, 1}

    assert :sys.get_state(agent).assigns == %{counter: 2}

    GenServer.stop(agent)
  end
end
