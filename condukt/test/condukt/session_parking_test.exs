defmodule Condukt.SessionParkingTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.Lease
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

  # A local sandbox that reports the leases and process watches asked of it.
  defmodule WatchingSandbox do
    @behaviour Condukt.Sandbox

    alias Condukt.Sandbox.Local

    @impl true
    def init(opts) do
      {:ok, local} = Local.init(opts)
      {:ok, {local, Keyword.fetch!(opts, :test_pid)}}
    end

    @impl true
    def watch_process({_local, test_pid}, id, target), do: tap(:ok, fn _ -> send(test_pid, {:watch, id, target}) end)

    @impl true
    def activity({_local, test_pid}, activity), do: tap(:ok, fn _ -> send(test_pid, {:activity, activity}) end)

    @impl true
    def shutdown({local, _}), do: Local.shutdown(local)
    @impl true
    def read_file({local, _}, path), do: Local.read_file(local, path)
    @impl true
    def write_file({local, _}, path, content), do: Local.write_file(local, path, content)
    @impl true
    def edit_file({local, _}, path, old, new), do: Local.edit_file(local, path, old, new)
    @impl true
    def exec({local, _}, command, opts), do: Local.exec(local, command, opts)
    @impl true
    def cwd({local, _}), do: Local.cwd(local)
    @impl true
    def start_process({local, _}, id, command, opts), do: Local.start_process(local, id, command, opts)
    @impl true
    def read_process({local, _}, id, offset, opts), do: Local.read_process(local, id, offset, opts)
    @impl true
    def stop_process({local, _}, id), do: Local.stop_process(local, id)
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

    assert_receive {:about_to_park, tool}, 1_000
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

  test "a parked call that may change the sandbox holds back the calls after it until it wakes" do
    test_pid = self()

    deploy =
      Condukt.tool(
        name: "deploy",
        description: "deploy",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _ctx -> {:park, nil, signals: [{Answer, "deployed"}]} end,
        wake: fn {:signal, _key, text}, nil, _ctx -> {:ok, text} end
      )

    check =
      tool("check", fn _args, _ctx ->
        send(test_pid, :check_started)
        {:ok, "checked"}
      end)

    pid =
      start_session(
        [tool_calls([{"call_d", "deploy", %{}}, {"call_c", "check", %{}}]), LLMProvider.text_response("done")],
        [deploy, check]
      )

    run = Task.async(fn -> Condukt.run(pid, "go") end)

    assert %{tool_calls: [%{tool_call_id: "call_d"}]} = await(fn -> Session.waiting(pid) end)
    refute_receive :check_started, 100

    assert Condukt.signal(pid, Answer, "deployed", %{"text" => "live"}) == :ok
    assert_receive :check_started, 1_000
    assert Task.await(run) == {:ok, "done"}
    assert tool_result(pid, "call_d") == "live"
  end

  describe "Bash on a sandbox that runs processes" do
    @describetag :tmp_dir

    test "a long command parks, streams its output to subscribers, the notifier, and the view, and wakes when it exits",
         %{tmp_dir: tmp_dir} do
      command = "echo first; while [ ! -e gate ]; do sleep 0.05; done; echo second"

      responses = [
        stream_response(
          [ReqLLM.StreamChunk.tool_call("Bash", %{"command" => command}, %{id: "call_1", index: 0})],
          :tool_calls
        ),
        stream_response([ReqLLM.StreamChunk.text("done")])
      ]

      pid = start_session([], [{Condukt.Tools.Bash, park_after: 50}], sandbox: local_sandbox(tmp_dir))
      stub_stream(pid, responses)
      stream = Task.async(fn -> pid |> Condukt.stream("go") |> Enum.to_list() end)

      assert %{tool_calls: [%{tool_call_id: "call_1", signals: [{Condukt.Tools.Bash.Exited, "bash:call_1"}]}]} =
               await(fn -> Session.waiting(pid) end)

      assert await(fn -> match?(%{output: "first\n"}, view_tool(pid, "call_1")) end)
      File.touch!(Path.join(tmp_dir, "gate"))

      events = Task.await(stream)

      assert [
               {:tool_output, "call_1", "first\n"},
               {:tool_output, "call_1", "second\n"},
               {:tool_result, "call_1", "first\nsecond\n"}
             ] = Enum.filter(events, &(elem_tag(&1) in [:tool_output, :tool_result]))

      assert {:text, "done"} in events
      assert_received {:notified, {:tool_output, "call_1", "first\n"}}
    end

    test "aborting the turn kills its command, whether parked or in the foreground", %{tmp_dir: tmp_dir} do
      for {park_after, call_id} <- [{50, "parked"}, {60_000, "foreground"}] do
        pid_file = Path.join(tmp_dir, call_id <> ".pid")
        command = "echo $$ > #{pid_file}; exec sleep 60"

        pid =
          start_session(
            [tool_calls([{call_id, "Bash", %{"command" => command}}])],
            [{Condukt.Tools.Bash, park_after: park_after}],
            sandbox: local_sandbox(tmp_dir)
          )

        run = Task.async(fn -> Condukt.run(pid, "go") end)
        os_pid = await(fn -> File.read(pid_file) |> then(&(match?({:ok, <<_, _::binary>>}, &1) && elem(&1, 1))) end)
        if park_after == 50, do: await(fn -> Session.waiting(pid) end)

        assert Condukt.abort(pid) == :ok
        assert Task.await(run) == {:error, :aborted}
        assert await(fn -> not os_alive?(String.trim(os_pid)) end)
        stop_supervised!(ParkingAgent)
      end
    end

    test "a drained session leaves its parked command running, which its sandbox watched under a lease",
         %{tmp_dir: tmp_dir} do
      pid_file = Path.join(tmp_dir, "drained.pid")
      command = "echo $$ > #{pid_file}; exec sleep 60"
      {model, _id} = LLMProvider.model([tool_calls([{"call_1", "Bash", %{"command" => command}}])])

      {:ok, session} =
        Condukt.Sessions.start(ParkingAgent,
          model: model,
          tools: [{Condukt.Tools.Bash, park_after: 50}],
          system_prompt: nil,
          load_project_instructions: false,
          lease_interval: 50,
          sandbox: {WatchingSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"), test_pid: self()}
        )

      id = Session.id(session)
      spawn(fn -> Condukt.run(session, "go") end)
      await(fn -> Session.waiting(session) end)
      # The call parks after 50 ms, which a loaded machine's shell can take to start.
      os_pid =
        await(
          fn ->
            case File.read(pid_file) do
              {:ok, pid} when pid != "" -> String.trim(pid)
              _ -> nil
            end
          end,
          400
        )

      on_exit(fn -> System.cmd("kill", [os_pid]) end)

      assert_receive {:watch, "condukt-bash:" <> _,
                      %{session_id: ^id, signal: Condukt.Tools.Bash.Exited, key: "bash:call_1"}}

      # Taken when the turn started and renewed while it is parked.
      assert_receive {:activity, :active}
      assert_receive {:activity, :active}, 1_000

      assert Condukt.Sessions.stop(id, drain: true) == :ok
      refute Process.alive?(session)
      Process.sleep(100)
      assert os_alive?(os_pid)
      # A drained session leaves the sandbox to the node taking it over.
      refute_received {:activity, :idle}
    end

    test "a session gives its sandbox's lease back once its turn ends", %{tmp_dir: tmp_dir} do
      pid =
        start_session([LLMProvider.text_response("done")], [],
          sandbox: {WatchingSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"), test_pid: self()}
        )

      assert Condukt.run(pid, "go") == {:ok, "done"}
      assert_receive {:activity, :active}
      assert_receive {:activity, :idle}, 3_000
    end

    test "a sandbox that sessions share stays leased until none of them has a turn", %{tmp_dir: tmp_dir} do
      {:ok, sandbox} =
        Condukt.Sandbox.new(WatchingSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "p"), test_pid: self())

      parent = Lease.start(sandbox, [])
      # A sub-agent given the parent's sandbox holds the same lease.
      child = Lease.start(parent, [])
      assert child.lease == parent.lease

      holder = fn -> spawn(fn -> receive do: (fun -> fun.()) end) end
      run_in = fn pid, fun -> send(pid, fun) end
      parent_session = holder.()
      child_session = holder.()

      run_in.(parent_session, fn -> Lease.active(parent) && Process.sleep(:infinity) end)
      run_in.(child_session, fn -> Lease.active(child) && Process.sleep(:infinity) end)
      assert_receive {:activity, :active}

      # The parent's turn ends while the child works on.
      Process.exit(parent_session, :kill)
      refute_receive {:activity, _activity}, 1_500

      # A holder that exits counts as idle.
      Process.exit(child_session, :kill)
      assert_receive {:activity, :idle}, 3_000
    end
  end

  @tag :tmp_dir
  test "a tool given its own sandbox runs there, beside the session's", %{tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "mac"))
    File.write!(Path.join(tmp_dir, "mac/where"), "mac")
    File.write!(Path.join(tmp_dir, "where"), "linux")
    {:ok, mac} = Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: Path.join(tmp_dir, "mac"))

    pid =
      start_session(
        [
          tool_calls([{"c1", "Read", %{"path" => "where"}}, {"c2", "MacRead", %{"path" => "where"}}]),
          LLMProvider.text_response("done")
        ],
        [Condukt.Tools.Read, {Condukt.Tools.Read, name: "MacRead", sandbox: mac}],
        sandbox: {Condukt.Sandbox.Local, cwd: tmp_dir}
      )

    assert Condukt.run(pid, "go") == {:ok, "done"}
    assert tool_result(pid, "c1") =~ "linux"
    assert tool_result(pid, "c2") =~ "mac"
  end

  defp local_sandbox(tmp_dir), do: {Condukt.Sandbox.Local, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes")}

  defp view_tool(pid, id) do
    case Condukt.view(pid).run do
      %{items: items} -> Enum.find(items, &match?(%{type: :tool, id: ^id}, &1))
      nil -> nil
    end
  end

  defp elem_tag(event) when is_tuple(event), do: elem(event, 0)
  defp elem_tag(event), do: event

  defp os_alive?(pid), do: match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

  # Read-only, so the calls of one round run together and park side by side.
  defp tool(name, call, wake \\ nil, cancel \\ nil) do
    Condukt.tool(
      name: name,
      description: name,
      parameters: %{type: "object", properties: %{}},
      call: call,
      wake: wake,
      cancel: cancel,
      read_only: true
    )
  end

  defp tool_calls(calls) do
    tool_calls = for {id, name, args} <- calls, do: ToolCall.new(id, name, JSON.encode!(args))
    LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: tool_calls}, :tool_calls)
  end

  defp start_session(responses, tools, opts \\ []) do
    {model, _model_id} = LLMProvider.model(responses)

    start_supervised!(
      {ParkingAgent,
       [
         model: model,
         tools: tools,
         system_prompt: nil,
         load_project_instructions: false,
         notifier: {RecordingNotifier, test_pid: self()}
       ] ++ opts}
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
