defmodule Condukt.HooksTest do
  use ExUnit.Case, async: true

  alias Condukt.Hooks
  alias Condukt.Message
  alias Condukt.Test.LLMProvider
  alias ReqLLM.ToolCall

  @moduletag :capture_log

  defmodule HookedAgent do
    use Condukt
  end

  defmodule Declared do
    @behaviour Hooks

    @impl true
    def before_tool(_call, _context), do: {:block, "declared hook"}
  end

  defmodule DeclaringAgent do
    use Condukt

    @impl true
    def hooks, do: [Declared]
  end

  # Each hook reports what it saw to the test and does what its opts say.
  defmodule Before do
    @behaviour Hooks

    @impl true
    def before_tool(call, %{opts: opts}) do
      send(opts[:test_pid], {:before, opts[:name], call.args, self()})
      act(opts[:action], call)
    end

    defp act(nil, _call), do: :ok
    defp act({:put, key, value}, call), do: {:rewrite, Map.put(call.args, key, value)}
    defp act({:block, reason}, _call), do: {:block, reason}
    defp act({:return, value}, _call), do: value
    defp act(:raise, _call), do: raise("boom")
    defp act({:raise, message}, _call), do: raise(message)
    defp act(:throw, _call), do: throw(:nope)
    defp act(:kill_self, _call), do: Process.exit(self(), :kill)
    defp act(:wait, _call), do: receive(do: (:never -> :ok))
  end

  defmodule After do
    @behaviour Hooks

    @impl true
    def after_tool(call, result, %{opts: opts}) do
      send(opts[:test_pid], {:after, opts[:name], call.args, result})

      case opts[:action] do
        nil -> :ok
        {:append, suffix} -> {:replace, {:ok, elem(result, 1) <> suffix}}
        {:return, value} -> value
        :raise -> raise "boom"
      end
    end
  end

  defmodule Yield do
    @behaviour Hooks

    @impl true
    def on_yield(message, %{opts: opts, turn: turn}) do
      send(opts[:test_pid], {:yield, opts[:name], Message.text(message), turn, self()})

      case opts[:action] do
        {:continue_once, text} -> if turn == 0, do: {:continue, text}, else: :ok
        {:return, value} -> value
        :raise -> raise "boom"
        :wait -> receive(do: (:never -> :ok))
        nil -> :ok
      end
    end
  end

  defp echo_tool(test_pid) do
    Condukt.tool(
      name: "echo",
      description: "echoes its arguments",
      parameters: %{type: "object", properties: %{}},
      call: fn args, _context ->
        send(test_pid, {:tool_ran, args})
        {:ok, "ran with " <> JSON.encode!(args)}
      end
    )
  end

  defp tool_call_response(args) do
    calls_response([ToolCall.new("call_1", "echo", JSON.encode!(args))])
  end

  defp calls_response(calls) do
    LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: calls}, :tool_calls)
  end

  defp start(responses, hooks, opts \\ []) do
    {model, _} = LLMProvider.model(responses)

    {:ok, pid} =
      HookedAgent.start_link(
        Keyword.merge(
          [model: model, tools: [echo_tool(self())], hooks: hooks, load_project_instructions: false],
          opts
        )
      )

    pid
  end

  defp tool_result(pid) do
    pid |> Condukt.Session.history() |> Enum.find(&(&1.role == :tool_result)) |> Message.tool_result_content()
  end

  defp attach_tool_stop do
    test_pid = self()
    handler_id = "hook-tool-stop-#{inspect(make_ref())}"

    :telemetry.attach(
      handler_id,
      [:condukt, :tool_call, :stop],
      fn _event, _measurements, metadata, _ -> send(test_pid, {:tool_stop, metadata.args, metadata.result}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "before_tool rewrites pass down the chain and the call runs with the last arguments" do
    attach_tool_stop()

    pid =
      start([tool_call_response(%{"a" => 1}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), name: :first, action: {:put, "b", 2}},
        {Before, test_pid: self(), name: :second, action: {:put, "a", 3}},
        {After, test_pid: self(), name: :after}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert_received {:before, :first, %{"a" => 1}, _}
    assert_received {:before, :second, %{"a" => 1, "b" => 2}, _}
    assert_received {:tool_ran, %{"a" => 3, "b" => 2}}
    assert_received {:after, :after, %{"a" => 3, "b" => 2}, {:ok, _}}
    assert_received {:tool_stop, %{"a" => 3, "b" => 2}, _}
  end

  test "the first before_tool block stops the chain and the model gets the reason" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), name: :first},
        {Before, test_pid: self(), name: :blocker, action: {:block, "needs approval"}},
        {Before, test_pid: self(), name: :third},
        {After, test_pid: self(), name: :after}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert_received {:before, :blocker, _, _}
    refute_received {:before, :third, _, _}
    refute_received {:tool_ran, _}
    assert tool_result(pid) == {:error, "Tool call blocked: needs approval"}
    assert_received {:after, :after, %{}, {:error, "Tool call blocked: needs approval"}}
  end

  test "a before_tool hook that crashes blocks only its call, and after_tool still sees it" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), name: :crash, action: :raise},
        {Before, test_pid: self(), name: :later},
        {After, test_pid: self(), name: :after}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")

    refute_received {:before, :later, _, _}
    refute_received {:tool_ran, _}
    assert tool_result(pid) == {:error, "Tool call blocked: boom"}
    assert_received {:after, :after, %{}, {:error, "Tool call blocked: boom"}}
  end

  test "blocking a call in a session with secrets redacts the reason and the run goes on" do
    pid =
      start(
        [tool_call_response(%{}), LLMProvider.text_response("done")],
        [{Before, test_pid: self(), name: :gate, action: {:raise, "upstream said secret-token"}}],
        secrets: [GH_TOKEN: {:static, "secret-token"}]
      )

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert {:error, "Tool call blocked: upstream said " <> rest} = tool_result(pid)
    refute rest =~ "secret-token"
  end

  test "a hook that throws gives the model its reason without a stack trace" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [{Before, test_pid: self(), action: :throw}])

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert tool_result(pid) == {:error, "Tool call blocked: {:nocatch, :nope}"}
  end

  test "a hook killed without an abort fails its call instead of reading as an abort" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), action: :kill_self},
        {After, test_pid: self(), name: :after}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert tool_result(pid) == {:error, "Tool call blocked: :killed"}
    assert_received {:after, :after, _, {:error, "Tool call blocked: :killed"}}
  end

  test "after_tool replacements pass down the chain" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {After, test_pid: self(), name: :first, action: {:append, " +1"}},
        {After, test_pid: self(), name: :second, action: {:append, " +2"}}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert_received {:after, :first, _, {:ok, "ran with {}"}}
    assert_received {:after, :second, _, {:ok, "ran with {} +1"}}
    assert tool_result(pid) == "ran with {} +1 +2"
  end

  test "an after_tool hook that crashes fails its call" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {After, test_pid: self(), name: :crash, action: :raise},
        {After, test_pid: self(), name: :later}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert_received {:tool_ran, _}
    refute_received {:after, :later, _, _}
    assert tool_result(pid) == {:error, "after_tool hook failed: boom"}
  end

  test "invalid returns fail what the hook was deciding" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), name: :bad, action: {:return, {:rewrite, "not a map"}}}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")
    refute_received {:tool_ran, _}
    assert {:error, "Tool call blocked: " <> reason} = tool_result(pid)
    assert reason =~ "invalid value"

    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {After, test_pid: self(), name: :bad, action: {:return, {:replace, :not_a_result}}},
        {Yield, test_pid: self(), name: :bad, action: {:return, {:continue, 1}}}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert {:error, "after_tool hook failed: " <> _} = tool_result(pid)
    assert [_user, _call, _result, %{role: :assistant}] = Condukt.Session.history(pid)

    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {After, test_pid: self(), name: :bad, action: {:return, {:replace, {:ok, {:not, :json}}}}}
      ])

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert {:error, "after_tool hook failed: " <> reason} = tool_result(pid)
    assert reason =~ "invalid value"
    assert {:ok, "next"} = run_again(pid)
  end

  # A session that is not wedged takes another prompt.
  defp run_again(pid) do
    {model, _} = LLMProvider.model([LLMProvider.text_response("next")])
    :sys.replace_state(pid, &put_in(&1.llm.model, model))
    Condukt.run(pid, "again")
  end

  test "on_yield continues the run with a user message, and the first continue stops the chain" do
    pid =
      start([LLMProvider.text_response("draft"), LLMProvider.text_response("final")], [
        {Yield, test_pid: self(), name: :reviewer, action: {:continue_once, "Check your work."}},
        {Yield, test_pid: self(), name: :second}
      ])

    assert {:ok, "final"} = Condukt.run(pid, "go")

    assert_received {:yield, :reviewer, "draft", 0, _}
    refute_received {:yield, :second, "draft", 0, _}
    assert_received {:yield, :second, "final", 1, _}

    assert [
             %{role: :user, content: "go"},
             %{role: :assistant},
             %{role: :user, content: "Check your work."},
             %{role: :assistant}
           ] = Condukt.Session.history(pid)
  end

  test "on_yield continues a streaming run" do
    pid = start([], [{Yield, test_pid: self(), name: :reviewer, action: {:continue_once, "Again."}}])
    streams = [text_stream("draft"), text_stream("final")]
    replies = start_supervised!({Agent, fn -> streams end})

    Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
      stream = Agent.get_and_update(replies, fn [stream | rest] -> {stream, rest} end)
      {:ok, %{stream | model: ReqLLM.model!(model), context: context}}
    end)

    Mimic.allow(ReqLLM, self(), pid)

    events = pid |> Condukt.stream("go") |> Enum.to_list()

    assert Enum.count(events, &(&1 == :turn_start)) == 2
    assert {:text, "final"} in events
    assert_received {:yield, :reviewer, "draft", 0, _}
    assert %{role: :user, content: "Again."} = Enum.at(Condukt.Session.history(pid), 2)
  end

  defp text_stream(text) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: :stop} end}, id: make_ref())

    %ReqLLM.StreamResponse{
      stream: [ReqLLM.StreamChunk.text(text)],
      metadata_handle: metadata,
      cancel: fn -> :ok end,
      model: nil,
      context: nil
    }
  end

  test "an on_yield hook that crashes leaves the answer standing" do
    pid =
      start([LLMProvider.text_response("draft")], [
        {Yield, test_pid: self(), name: :crash, action: :raise},
        {Yield, test_pid: self(), name: :reviewer, action: {:continue_once, "Again."}}
      ])

    assert {:ok, "draft"} = Condukt.run(pid, "go")

    refute_received {:yield, :reviewer, _, _, _}
    assert [%{role: :user}, %{role: :assistant}] = Condukt.Session.history(pid)
  end

  test "on_yield is not asked on the run's last turn, so the answer stands" do
    pid =
      start([LLMProvider.text_response("only")], [
        {Yield, test_pid: self(), name: :reviewer, action: {:return, {:continue, "Again."}}}
      ])

    assert {:ok, "only"} = Condukt.run(pid, "go", max_turns: 1)

    refute_received {:yield, :reviewer, _, _, _}
    assert [%{role: :user}, %{role: :assistant}] = Condukt.Session.history(pid)
  end

  test "aborting the run stops a before_tool hook that waits, and the call does not run" do
    pid =
      start([tool_call_response(%{}), LLMProvider.text_response("done")], [
        {Before, test_pid: self(), name: :gate, action: :wait}
      ])

    run = Task.async(fn -> Condukt.run(pid, "go") end)
    assert_receive {:before, :gate, _, hook}
    hook_ref = Process.monitor(hook)

    assert :ok = Condukt.abort(pid)
    assert {:error, :aborted} = Task.await(run)

    assert_receive {:DOWN, ^hook_ref, :process, ^hook, _reason}
    refute_received {:tool_ran, _}
  end

  test "aborting the run stops an on_yield hook that waits" do
    pid = start([LLMProvider.text_response("draft")], [{Yield, test_pid: self(), name: :review, action: :wait}])

    run = Task.async(fn -> Condukt.run(pid, "go") end)
    assert_receive {:yield, :review, "draft", 0, hook}, 1_000
    hook_ref = Process.monitor(hook)

    assert :ok = Condukt.abort(pid)
    assert {:error, :aborted} = Task.await(run)
    assert_receive {:DOWN, ^hook_ref, :process, ^hook, _reason}
  end

  test "with hooks, every read-only tool call in a response runs at once, more than there are schedulers" do
    test_pid = self()
    count = System.schedulers_online() + 1

    barrier =
      Condukt.tool(
        name: "barrier",
        description: "waits for the test",
        parameters: %{type: "object", properties: %{}},
        read_only: true,
        call: fn _args, _context ->
          send(test_pid, {:started, self()})
          receive(do: (:go -> {:ok, "passed"}))
        end
      )

    calls = for n <- 1..count, do: ToolCall.new("call_#{n}", "barrier", "{}")

    pid =
      start([calls_response(calls), LLMProvider.text_response("done")], [{Before, test_pid: self(), name: :pass}],
        tools: [barrier]
      )

    run = Task.async(fn -> Condukt.run(pid, "go") end)

    started = for _ <- 1..count, do: assert_receive({:started, tool}, 1_000) && tool
    Enum.each(started, &send(&1, :go))

    assert {:ok, "done"} = Task.await(run)
  end

  test "a tool call that exits fails alone and the run goes on" do
    exiting =
      Condukt.tool(
        name: "exiting",
        description: "exits",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context -> exit(:boom) end
      )

    pid =
      start(
        [calls_response([ToolCall.new("call_1", "exiting", "{}")]), LLMProvider.text_response("done")],
        [],
        tools: [exiting]
      )

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert tool_result(pid) == {:error, ":boom"}
  end

  test "an after_tool replacement is redacted before the model sees it" do
    pid =
      start(
        [tool_call_response(%{}), LLMProvider.text_response("done")],
        [{After, test_pid: self(), name: :leak, action: {:return, {:replace, {:ok, "token: secret-token"}}}}],
        secrets: [GH_TOKEN: {:static, "secret-token"}]
      )

    assert {:ok, "done"} = Condukt.run(pid, "go")

    assert tool_result(pid) =~ "token: "
    refute tool_result(pid) =~ "secret-token"
  end

  test "the agent's hooks/0 apply unless the :hooks option replaces them" do
    {model, _} = LLMProvider.model([tool_call_response(%{}), LLMProvider.text_response("done")])
    {:ok, pid} = DeclaringAgent.start_link(model: model, tools: [echo_tool(self())], load_project_instructions: false)

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert tool_result(pid) == {:error, "Tool call blocked: declared hook"}

    {model, _} = LLMProvider.model([tool_call_response(%{}), LLMProvider.text_response("done")])

    {:ok, pid} =
      DeclaringAgent.start_link(model: model, tools: [echo_tool(self())], hooks: [], load_project_instructions: false)

    assert {:ok, "done"} = Condukt.run(pid, "go")
    assert tool_result(pid) == "ran with {}"
  end

  test "invalid hook specs fail the session start" do
    assert {:error, {:invalid_hook, "nope"}} = HookedAgent.start_link(hooks: ["nope"], load_project_instructions: false)
    assert {:error, {:hook_not_loaded, Missing.Hook, :nofile}} = HookedAgent.start_link(hooks: [Missing.Hook])
  end
end
