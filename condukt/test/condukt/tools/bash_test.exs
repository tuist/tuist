defmodule Condukt.Tools.BashTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Condukt.Sandbox
  alias Condukt.Test.OutageSandbox
  alias Condukt.Tools.Bash

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "is replay-safe only when its host opts in" do
    refute Condukt.Tool.replay_safe?(Bash)
    refute Condukt.Tool.replay_safe?({Bash, []})
    assert Condukt.Tool.replay_safe?({Bash, replay_safe: true})
  end

  test "executes simple command", %{tmp_dir: tmp_dir, context: context} do
    expect_sandbox_bash("echo hello", tmp_dir, "hello\n", 0, fn opts ->
      assert opts[:timeout] == 120_000
      assert {"TERM", "dumb"} in opts[:env]
    end)

    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "passes session secrets as environment variables", %{tmp_dir: tmp_dir, context: context} do
    context = Map.put(context, :secrets, %Condukt.Secrets{env: [{"GH_TOKEN", "secret-token"}]})

    expect_sandbox_bash("echo $GH_TOKEN", tmp_dir, "secret-token\n", 0, fn opts ->
      assert {"GH_TOKEN", "secret-token"} in opts[:env]
    end)

    {:ok, result} = Bash.call(%{"command" => "echo $GH_TOKEN"}, context)

    assert String.contains?(result, "secret-token")
  end

  test "captures stderr", %{tmp_dir: tmp_dir, context: context} do
    expect_sandbox_bash("echo error >&2", tmp_dir, "error\n")

    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{tmp_dir: tmp_dir, context: context} do
    expect_sandbox_bash("exit 42", tmp_dir, "", 42)

    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{tmp_dir: tmp_dir, context: context} do
    expect_sandbox_bash("pwd", tmp_dir, "#{tmp_dir}\n")

    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, tmp_dir)
  end

  test "accepts cwd argument relative to context cwd", %{tmp_dir: tmp_dir, context: context} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    expect_sandbox_bash("pwd", nested_dir, "#{nested_dir}\n")

    {:ok, result} = Bash.call(%{"command" => "pwd", "cwd" => "nested"}, context)

    assert String.contains?(result, nested_dir)
  end

  test "returns runner errors as command failures", %{context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", _script, "condukt-capture", _capture_path, "pwd"], _opts ->
      raise ErlangError, original: :enoent
    end)

    assert {:error, "Command failed: \"Erlang error: :enoent\""} =
             Bash.call(%{"command" => "pwd"}, context)
  end

  describe "on a sandbox that runs processes, in a session" do
    # The test process stands in for the session: tool output reaches it as
    # casts.
    setup %{tmp_dir: tmp_dir} do
      {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"))
      turn_ref = make_ref()

      context = %{
        sandbox: sandbox,
        opts: [park_after: 5_000],
        session_id: "session-1",
        tool_call_id: "call-1",
        agent: self(),
        turn_ref: turn_ref
      }

      %{context: context, sandbox: sandbox, turn_ref: turn_ref}
    end

    test "streams output while the command runs and returns all of it when it ends",
         %{context: context, turn_ref: turn_ref, tmp_dir: tmp_dir} do
      command = "echo first; while [ ! -e gate ]; do sleep 0.05; done; echo second; exit 2"
      call = Task.async(fn -> Bash.call(%{"command" => command}, context) end)

      assert_receive {:"$gen_cast", {:tool_output, ^turn_ref, {:tool_output, "call-1", "first\n"}}}, 2_000
      assert Task.yield(call, 0) == nil

      File.touch!(Path.join(tmp_dir, "gate"))

      assert_receive {:"$gen_cast", {:tool_output, ^turn_ref, {:tool_output, "call-1", "second\n"}}}, 2_000
      assert Task.await(call) == {:ok, "first\nsecond\n\n\n(exit code: 2)"}
    end

    test "a call that runs again follows the command its id names instead of starting it twice",
         %{context: context, sandbox: sandbox, tmp_dir: tmp_dir} do
      command = "echo start >> starts; sleep 0.2; echo done"
      assert :ok = Sandbox.start_process(sandbox, Bash.process_id("session-1", "call-1"), command)

      assert Bash.call(%{"command" => command}, context) == {:ok, "done\n"}
      assert File.read!(Path.join(tmp_dir, "starts")) == "start\n"
      assert {:error, :not_found} = Sandbox.read_process(sandbox, Bash.process_id("session-1", "call-1"), 0)
    end

    test "keeps the first and last lines of long output", %{context: context} do
      assert {:ok, result} = Bash.call(%{"command" => "seq 1 100000"}, context)

      assert result =~ ~r/\A1\n2\n3\n/
      assert String.ends_with?(result, "\n99999\n100000\n")
      assert result =~ ~r/\n\.\.\. \(\d+ bytes of output truncated\) \.\.\.\n/
      assert byte_size(result) <= 50 * 1024 + 100
      assert length(String.split(result, "\n")) <= 2_000 + 4
    end

    test "a timeout kills the command and returns what it printed", %{context: context} do
      assert {:error, message} = Bash.call(%{"command" => "echo partial; sleep 5", "timeout" => 0.3}, context)
      assert message == "Command timed out after 0 seconds\n\npartial\n"
    end

    test "the call ending abnormally while its session lives kills the command, as an abort does",
         %{context: context, sandbox: sandbox, tmp_dir: tmp_dir} do
      call = spawn(fn -> Bash.call(%{"command" => "echo $$ > pid; exec sleep 60"}, context) end)
      pid = await_file(Path.join(tmp_dir, "pid"))

      Process.exit(call, :shutdown)

      assert await(fn -> not alive?(pid) end)

      assert await(fn ->
               Sandbox.read_process(sandbox, Bash.process_id("session-1", "call-1"), 0) == {:error, :not_found}
             end)
    end

    test "a read that fails as the call wakes parks it again, leaving the command running",
         %{context: context, tmp_dir: tmp_dir} do
      {:ok, sandbox} = Sandbox.new(OutageSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"))
      context = %{context | sandbox: sandbox, opts: [park_after: 50]}
      command = "while [ ! -e gate ]; do sleep 0.05; done; echo built"
      assert {:park, state, _opts} = Bash.call(%{"command" => command}, context)

      File.touch!(Path.join(tmp_dir, "outage"))
      event = {:signal, {Bash.Exited, "bash:call-1"}, {:error, :unavailable}}
      assert {:park, state, opts} = Bash.wake(event, state, context)
      assert opts[:signals] == [{Bash.Exited, "bash:call-1:2"}]

      File.rm!(Path.join(tmp_dir, "outage"))
      File.touch!(Path.join(tmp_dir, "gate"))

      assert_receive {:"$gen_call", from, {:signal, {Bash.Exited, "bash:call-1:2"}, {:exited, 0}}}, 5_000
      GenServer.reply(from, :ok)
      assert Bash.wake({:signal, {Bash.Exited, "bash:call-1:2"}, {:exited, 0}}, state, context) == {:ok, "built\n"}
    end

    test "parks a command that outlasts :park_after and wakes to its result", %{context: context, tmp_dir: tmp_dir} do
      context = %{context | opts: [park_after: 50]}
      command = "while [ ! -e gate ]; do sleep 0.05; done; echo built"

      assert {:park, state, opts} = Bash.call(%{"command" => command}, context)
      assert opts[:signals] == [{Bash.Exited, "bash:call-1"}]
      assert DateTime.diff(opts[:until], DateTime.utc_now(), :second) in 140..150

      File.touch!(Path.join(tmp_dir, "gate"))

      # The watcher delivers the exit signal to the session, here the test process.
      assert_receive {:"$gen_call", from, {:signal, {Bash.Exited, "bash:call-1"}, {:exited, 0}}}, 2_000
      GenServer.reply(from, :ok)

      assert Bash.wake({:signal, {Bash.Exited, "bash:call-1"}, {:exited, 0}}, state, context) == {:ok, "built\n"}
    end
  end

  defp await(fun, attempts \\ 200) do
    if fun.() or attempts == 0, do: fun.(), else: Process.sleep(10) && await(fun, attempts - 1)
  end

  defp await_file(path, attempts \\ 200) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        String.trim(content)

      _other when attempts > 0 ->
        Process.sleep(10)
        await_file(path, attempts - 1)
    end
  end

  defp alive?(pid), do: match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

  defp expect_sandbox_bash(command, cwd, output, exit_code \\ 0, assert_opts \\ fn _opts -> :ok end) do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", script, "condukt-capture", capture_path, ^command], opts ->
      assert script =~ ~s(exec > "$1" 2>&1)
      assert script =~ ~s(exec bash -c "$2")
      assert opts[:cd] == cwd
      assert opts[:stderr_to_stdout] == true
      assert opts[:parallelism] == false
      assert_opts.(opts)

      File.write!(capture_path, output)

      {"", exit_code}
    end)
  end
end
