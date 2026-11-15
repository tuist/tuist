defmodule Condukt.SessionParkingTest do
  use ExUnit.Case, async: true

  alias Condukt.Session
  alias Condukt.Test.LLMProvider
  alias ReqLLM.ToolCall

  defmodule ParkingAgent do
    use Condukt

    @impl true
    def init(_opts), do: {:ok, :ok}
  end

  defmodule Answer do
    @behaviour Condukt.Signal

    @impl true
    def cast(%{"text" => text}) when is_binary(text), do: {:ok, text}
    def cast(_value), do: {:error, :expected_text}
  end

  defmodule RecordingNotifier do
    @behaviour Condukt.Notifier

    @impl true
    def publish(_session_id, event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:notified, event})
      :ok
    end
  end

  test "a parked tool waits for its signal, wakes, and the run finishes" do
    test_pid = self()

    ask =
      tool(
        "ask",
        fn _args, _ctx -> {:park, :asked, signals: [{Answer, "answer"}], timeout: to_timeout(hour: 1)} end,
        fn {:signal, {Answer, "answer"}, text}, state, _ctx ->
          send(test_pid, {:woke, state})
          {:ok, "answer: " <> text}
        end
      )

    pid = start_session([tool_calls([{"call_1", "ask", %{}}]), LLMProvider.text_response("done")], [ask])
    run = Task.async(fn -> Condukt.run(pid, "go") end)

    waiting = await(fn -> Session.waiting(pid) end)

    assert %{
             tool_calls: [%{tool_call_id: "call_1", tool: "ask", signals: [{Answer, "answer"}], until: until}],
             wake_at: until
           } = waiting

    assert DateTime.diff(until, DateTime.utc_now(), :minute) in 58..60
    assert_receive {:notified, {:waiting, ^waiting}}

    assert Condukt.signal(pid, Answer, "answer", %{"text" => 42}) == {:error, {:invalid, :expected_text}}
    assert Condukt.signal(pid, Answer, "answer", %{"text" => "yes"}) == :ok
    assert Condukt.signal(pid, Answer, "answer", %{"text" => "again"}) == {:error, :duplicate}

    assert Task.await(run) == {:ok, "done"}
    assert_received {:woke, :asked}
    assert tool_result(pid, "call_1") == "answer: yes"
    assert Session.waiting(pid) == nil
    assert Condukt.signal(pid, Answer, "answer", %{"text" => "late"}) == {:error, :closed}
    assert Condukt.signal("no-such-session", Answer, "answer", %{"text" => "?"}) == {:error, :not_found}
  end

  test "a signal that arrives before the park is kept and wakes the park at once" do
    test_pid = self()

    ask =
      tool(
        "ask",
        fn _args, _ctx ->
          send(test_pid, {:about_to_park, self()})
          receive do: (:continue -> :ok)
          {:park, nil, signals: [{Answer, "early"}]}
        end,
        fn {:signal, {Answer, "early"}, text}, nil, _ctx -> {:ok, "got " <> text} end
      )

    pid = start_session([tool_calls([{"call_1", "ask", %{}}]), LLMProvider.text_response("done")], [ask])
    run = Task.async(fn -> Condukt.run(pid, "go") end)

    assert_receive {:about_to_park, tool}
    assert Condukt.signal(pid, Answer, "early", %{"text" => "webhook"}) == :ok
    send(tool, :continue)

    assert Task.await(run) == {:ok, "done"}
    assert tool_result(pid, "call_1") == "got webhook"
  end

  test "a deadline wakes its call alone and closes its keys, while another call keeps waiting" do
    wait_on = fn key, timeout ->
      tool(
        key,
        fn _args, _ctx -> {:park, key, signals: [{Answer, key}], timeout: timeout} end,
        fn
          :timeout, ^key, _ctx -> {:ok, key <> " timed out"}
          {:signal, {Answer, ^key}, text}, ^key, _ctx -> {:ok, key <> " got " <> text}
        end
      )
    end

    pid =
      start_session(
        [tool_calls([{"call_a", "a", %{}}, {"call_b", "b", %{}}]), LLMProvider.text_response("done")],
        [wait_on.("a", 30), wait_on.("b", to_timeout(hour: 1))]
      )

    run = Task.async(fn -> Condukt.run(pid, "go") end)

    assert %{tool_calls: [%{tool_call_id: "call_b"}]} =
             await(fn -> match?(%{tool_calls: [_]}, Session.waiting(pid)) && Session.waiting(pid) end)

    assert Condukt.signal(pid, Answer, "a", %{"text" => "too late"}) == {:error, :closed}
    assert Condukt.signal(pid, Answer, "b", %{"text" => "in time"}) == :ok

    assert Task.await(run) == {:ok, "done"}
    assert tool_result(pid, "call_a") == "a timed out"
    assert tool_result(pid, "call_b") == "b got in time"
  end

  test "a tool polls a slow job by parking on time and carrying its state" do
    poll_again = fn %{polls: polls, delay: delay} ->
      if polls == 3,
        do: {:ok, "done after #{polls} polls"},
        else: {:park, %{polls: polls + 1, delay: delay * 2}, timeout: delay}
    end

    poll =
      tool(
        "poll",
        fn _args, _ctx -> poll_again.(%{polls: 1, delay: 5}) end,
        fn :timeout, state, _ctx -> poll_again.(state) end
      )

    pid = start_session([tool_calls([{"call_1", "poll", %{}}]), LLMProvider.text_response("done")], [poll])

    assert Condukt.run(pid, "go") == {:ok, "done"}
    assert tool_result(pid, "call_1") == "done after 3 polls"
  end

  test "aborting a parked turn runs the tool's cancel with its state" do
    test_pid = self()

    ci =
      tool(
        "run_ci",
        fn %{"ref" => ref}, ctx -> {:park, %{ref: ref, build: 7}, signals: [{Answer, "ci-" <> ctx.tool_call_id}]} end,
        fn _event, _state, _ctx -> {:ok, "unused"} end,
        fn state, ctx -> send(test_pid, {:cancelled, state, ctx.tool_call_id}) end
      )

    pid = start_session([tool_calls([{"call_1", "run_ci", %{"ref" => "main"}}])], [ci])
    run = Task.async(fn -> Condukt.run(pid, "go") end)

    await(fn -> Session.waiting(pid) end)
    worker = Process.monitor(:sys.get_state(pid).turn.worker)
    assert Condukt.abort(pid) == :ok

    assert Task.await(run) == {:error, :aborted}
    assert_receive {:DOWN, ^worker, :process, _pid, _reason}
    assert_receive {:cancelled, %{ref: "main", build: 7}, "call_1"}
    assert Condukt.signal(pid, Answer, "ci-call_1", %{"text" => "passed"}) == {:error, :closed}
  end

  test "a wake closes its call's other keys, and a turn's keys stay closed in later turns" do
    decide =
      tool(
        "decide",
        fn _args, _ctx -> {:park, nil, signals: [{Answer, "approve"}, {Answer, "reject"}]} end,
        fn {:signal, {Answer, key}, _text}, nil, _ctx -> {:ok, key} end
      )

    later =
      tool(
        "later",
        fn _args, _ctx -> {:park, nil, signals: [{Answer, "later"}]} end,
        fn {:signal, _key, text}, nil, _ctx -> {:ok, text} end
      )

    pid =
      start_session(
        [
          tool_calls([{"call_1", "decide", %{}}]),
          LLMProvider.text_response("first"),
          tool_calls([{"call_2", "later", %{}}]),
          LLMProvider.text_response("second")
        ],
        [decide, later]
      )

    first = Task.async(fn -> Condukt.run(pid, "one") end)
    await(fn -> Session.waiting(pid) end)
    assert Condukt.signal(pid, Answer, "approve", %{"text" => "yes"}) == :ok
    assert Task.await(first) == {:ok, "first"}
    assert tool_result(pid, "call_1") == "approve"

    second = Task.async(fn -> Condukt.run(pid, "two") end)
    await(fn -> Session.waiting(pid) end)

    # A retry of the first turn's keys, while another turn runs.
    assert Condukt.signal(pid, Answer, "approve", %{"text" => "retry"}) == {:error, :closed}
    assert Condukt.signal(pid, Answer, "reject", %{"text" => "late"}) == {:error, :closed}

    assert Condukt.signal(pid, Answer, "later", %{"text" => "ok"}) == :ok
    assert Task.await(second) == {:ok, "second"}
  end

  test "aborting while a woken call runs cancels it, but not a woken call that already returned" do
    test_pid = self()
    until = DateTime.add(DateTime.utc_now(), 50, :millisecond)

    fast =
      tool(
        "fast",
        fn _args, _ctx -> {:park, :fast, until: until} end,
        fn :timeout, :fast, _ctx -> {:ok, "fast done"} end,
        fn state, _ctx -> send(test_pid, {:cancelled, state}) end
      )

    slow =
      tool(
        "slow",
        fn _args, _ctx -> {:park, :slow, until: until} end,
        fn :timeout, :slow, _ctx ->
          send(test_pid, {:slow_waking, self()})
          receive do: (:continue -> {:ok, "slow done"})
        end,
        fn state, _ctx -> send(test_pid, {:cancelled, state}) end
      )

    pid = start_session([tool_calls([{"call_f", "fast", %{}}, {"call_s", "slow", %{}}])], [fast, slow])
    run = Task.async(fn -> Condukt.run(pid, "go") end)

    assert_receive {:slow_waking, waking}, 1_000
    await(fn -> Map.keys(:sys.get_state(pid).turn.parking.running) == ["call_s"] end)
    worker = Process.monitor(:sys.get_state(pid).turn.worker)

    assert Condukt.abort(pid) == :ok
    assert Task.await(run) == {:error, :aborted}
    assert_receive {:cancelled, :slow}
    refute_receive {:cancelled, :fast}, 100

    # Let the admitted call finish while the session still lives.
    send(waking, :continue)
    assert_receive {:DOWN, ^worker, :process, _pid, _reason}
  end

  test "stopping a session cancels its parked calls" do
    test_pid = self()

    ci =
      tool(
        "run_ci",
        fn _args, ctx -> {:park, ctx.tool_call_id, signals: [{Answer, "ci-" <> ctx.tool_call_id}]} end,
        fn _event, _state, _ctx -> {:ok, "unused"} end,
        fn state, _ctx -> send(test_pid, {:cancelled, state}) end
      )

    {model, _id} = LLMProvider.model([tool_calls([{"call_1", "run_ci", %{}}])])
    opts = [model: model, tools: [ci], system_prompt: nil, load_project_instructions: false]

    {:ok, session} = Condukt.Sessions.start(ParkingAgent, opts)
    id = Session.id(session)
    on_exit(fn -> Condukt.Sessions.stop(id) end)
    run = Task.async(fn -> Condukt.run(session, "go") end)

    await(fn -> Session.waiting(session) end)
    assert Condukt.Sessions.stop(id) == :ok
    assert_receive {:cancelled, "call_1"}
    assert Task.await(run) == {:error, :aborted}
  end

  test "a park that cannot wake, has no wake callback, or reuses a key ends the call with an error result" do
    never = tool("never", fn _args, _ctx -> {:park, nil, signals: []} end, fn _event, _state, _ctx -> {:ok, ""} end)
    no_wake = tool("no_wake", fn _args, _ctx -> {:park, nil, timeout: 10} end)

    again =
      tool(
        "again",
        fn _args, _ctx -> {:park, nil, signals: [{Answer, "once"}]} end,
        fn {:signal, _key, _value}, nil, _ctx -> {:park, nil, signals: [{Answer, "once"}]} end
      )

    pid =
      start_session(
        [
          tool_calls([{"call_n", "never", %{}}, {"call_w", "no_wake", %{}}, {"call_a", "again", %{}}]),
          LLMProvider.text_response("done")
        ],
        [never, no_wake, again]
      )

    run = Task.async(fn -> Condukt.run(pid, "go") end)
    await(fn -> Session.waiting(pid) end)
    assert Condukt.signal(pid, Answer, "once", %{"text" => "x"}) == :ok

    assert Task.await(run) == {:ok, "done"}
    assert tool_result(pid, "call_n") == {:error, {:invalid_park, :never_wakes}}
    assert tool_result(pid, "call_w") == {:error, {:invalid_park, :no_wake_callback}}
    assert tool_result(pid, "call_a") == {:error, {:invalid_park, {:signal_key_used, {Answer, "once"}}}}
  end

  test "a streaming turn reports waiting, then the woken call's result, and ends once" do
    ask =
      tool(
        "ask",
        fn _args, _ctx -> {:park, nil, signals: [{Answer, "answer"}]} end,
        fn {:signal, {Answer, "answer"}, text}, nil, _ctx -> {:ok, "answer: " <> text} end
      )

    responses = [
      stream_response([ReqLLM.StreamChunk.tool_call("ask", %{}, %{id: "call_1", index: 0})], :tool_calls),
      stream_response([ReqLLM.StreamChunk.text("done")])
    ]

    pid = start_session([], [ask])
    stub_stream(pid, responses)
    stream = Task.async(fn -> pid |> Condukt.stream("go") |> Enum.to_list() end)

    await(fn -> Session.waiting(pid) end)
    assert Condukt.signal(pid, Answer, "answer", %{"text" => "yes"}) == :ok
    events = Task.await(stream)

    assert [{:waiting, %{tool_calls: [%{tool_call_id: "call_1"}], wake_at: nil}}, {:tool_result, "call_1", result}] =
             Enum.filter(events, &(match?({:tool_result, _, _}, &1) or match?({:waiting, _}, &1)))

    assert result == "answer: yes"
    assert {:text, "done"} in events
    assert Enum.count(events, &(&1 == :agent_end)) == 1
    assert List.last(events) == :agent_end
  end

  defp tool(name, call, wake \\ nil, cancel \\ nil) do
    Condukt.tool(
      name: name,
      description: name,
      parameters: %{type: "object", properties: %{}},
      call: call,
      wake: wake,
      cancel: cancel
    )
  end

  defp tool_calls(calls) do
    tool_calls = for {id, name, args} <- calls, do: ToolCall.new(id, name, JSON.encode!(args))
    LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: tool_calls}, :tool_calls)
  end

  defp start_session(responses, tools) do
    {model, _model_id} = LLMProvider.model(responses)

    start_supervised!(
      {ParkingAgent,
       model: model,
       tools: tools,
       system_prompt: nil,
       load_project_instructions: false,
       notifier: {RecordingNotifier, test_pid: self()}}
    )
  end

  defp tool_result(pid, id) do
    pid |> Condukt.history() |> Enum.find(&(&1.role == :tool_result and &1.tool_call_id == id)) |> Map.fetch!(:content)
  end

  defp await(fun, attempts \\ 200) do
    case fun.() do
      result when result in [nil, false] and attempts > 0 ->
        Process.sleep(5)
        await(fun, attempts - 1)

      result ->
        assert result
        result
    end
  end

  defp stub_stream(pid, responses) do
    responses = start_supervised!({Agent, fn -> responses end})

    Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
      response = Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)
      {:ok, %{response | model: ReqLLM.model!(model), context: context}}
    end)

    Mimic.allow(ReqLLM, self(), pid)
  end

  defp stream_response(chunks, finish_reason \\ :stop) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: finish_reason} end},
        id: make_ref()
      )

    %ReqLLM.StreamResponse{stream: chunks, metadata_handle: metadata, cancel: fn -> :ok end, model: nil, context: nil}
  end
end
