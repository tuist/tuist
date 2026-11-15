defmodule Condukt.Sandbox.ProcessesTest do
  # The shell runner that Kubernetes and Microsandbox use for detached
  # processes, run against the host's bash in place of a pod or a guest.
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.Processes

  @moduletag :tmp_dir

  if System.find_executable("setsid") == nil, do: @moduletag(skip: "needs setsid from util-linux")

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "processes")

    # Like a pod's exec: runs one script and returns when it exits, whatever
    # it left running.
    exec = fn script ->
      {output, exit_code} = System.cmd("bash", ["-c", script], cd: tmp_dir, stderr_to_stdout: true)
      {:ok, %{output: output, exit_code: exit_code}}
    end

    %{exec: exec, opts: [root: root], cwd: tmp_dir}
  end

  test "a process runs apart from the exec that started it, and its output reads from any offset",
       %{exec: exec, opts: opts, cwd: cwd} do
    gate = Path.join(cwd, "gate")
    command = "echo one; while [ ! -e #{gate} ]; do sleep 0.05; done; echo two; exit 3"

    assert :ok = Processes.start(exec, "p1", command, opts)
    assert {:ok, %{output: "one\n", offset: 4, size: 4, status: :running}} = await_output(exec, "p1", 0, opts, "one\n")

    File.touch!(gate)

    assert {:ok, %{output: "two\n", offset: 8, size: 8, status: {:exited, 3}}} =
             await_status(exec, "p1", 4, opts)

    assert {:ok, %{output: "ne\ntw", offset: 6}} = Processes.read(exec, "p1", 1, Keyword.put(opts, :max_bytes, 5))
  end

  test "starting an id again finds the process instead of running the command twice",
       %{exec: exec, opts: opts, cwd: cwd} do
    counter = Path.join(cwd, "starts")
    command = "echo start >> #{counter}; sleep 0.3"

    assert :ok = Processes.start(exec, "p2", command, opts)
    assert {:error, :already_started} = Processes.start(exec, "p2", command, opts)
    assert {:ok, %{status: {:exited, 0}}} = await_status(exec, "p2", 0, opts)
    assert {:error, :already_started} = Processes.start(exec, "p2", command, opts)
    assert File.read!(counter) == "start\n"
  end

  test "runs in cwd with env, and reports a timeout apart from an exit", %{exec: exec, opts: opts, cwd: cwd} do
    File.mkdir_p!(Path.join(cwd, "sub"))

    assert :ok =
             Processes.start(
               exec,
               "p3",
               "pwd; echo $GREETING",
               [cwd: Path.join(cwd, "sub"), env: [{"GREETING", "it's me"}]] ++ opts
             )

    assert {:ok, %{output: output, status: {:exited, 0}}} = await_status(exec, "p3", 0, opts)
    assert output == Path.join(cwd, "sub") <> "\nit's me\n"

    assert :ok = Processes.start(exec, "p4", "sleep 5", [timeout: 200] ++ opts)
    assert {:ok, %{status: :timeout}} = await_status(exec, "p4", 0, opts)

    # A command's own 124 is an exit, not a timeout.
    assert :ok = Processes.start(exec, "p4b", "exit 124", [timeout: 60_000] ++ opts)
    assert {:ok, %{status: {:exited, 124}}} = await_status(exec, "p4b", 0, opts)
  end

  test "a timeout kills what the command started in the background", %{exec: exec, opts: opts, cwd: cwd} do
    pid_file = Path.join(cwd, "bg.pid")
    assert :ok = Processes.start(exec, "p8", "sleep 60 & echo $! > #{pid_file}; wait", [timeout: 300] ++ opts)
    sleeper = await_file(pid_file)

    assert {:ok, %{status: :timeout}} = await_status(exec, "p8", 0, opts)
    refute alive?(sleeper)
  end

  test "stop kills the process with the processes it started, with or without a timeout, and forgets it",
       %{exec: exec, opts: opts, cwd: cwd} do
    for {id, extra} <- [{"p5", []}, {"p6", [timeout: 60_000]}] do
      pid_file = Path.join(cwd, id <> ".pid")
      assert :ok = Processes.start(exec, id, "sleep 60 & echo $! > #{pid_file}; wait", extra ++ opts)
      sleeper = await_file(pid_file)
      assert alive?(sleeper)

      assert :ok = Processes.stop(exec, id, opts)
      refute alive?(sleeper)
      assert {:error, :not_found} = Processes.read(exec, id, 0, opts)
    end

    assert :ok = Processes.stop(exec, "never-started", opts)
  end

  test "a process killed before it recorded its status reads as exited with no code",
       %{exec: exec, opts: opts, cwd: cwd} do
    assert :ok = Processes.start(exec, "p7", "sleep 60", opts)
    pid = await_file(Path.join([cwd, "processes", Processes.dir_name("p7"), "pid"]))

    System.cmd("kill", ["-KILL", "--", "-" <> pid])

    assert {:ok, %{status: {:exited, nil}}} = await_status(exec, "p7", 0, opts)
    assert :ok = Processes.stop(exec, "p7", opts)
  end

  defp await_output(exec, id, offset, opts, expected, attempts \\ 100) do
    case Processes.read(exec, id, offset, opts) do
      {:ok, %{output: ^expected}} = result ->
        result

      _other when attempts > 0 ->
        Process.sleep(20)
        await_output(exec, id, offset, opts, expected, attempts - 1)
    end
  end

  defp await_status(exec, id, offset, opts, attempts \\ 200) do
    case Processes.read(exec, id, offset, opts) do
      {:ok, %{status: :running}} when attempts > 0 ->
        Process.sleep(20)
        await_status(exec, id, offset, opts, attempts - 1)

      result ->
        result
    end
  end

  defp await_file(path, attempts \\ 100) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        String.trim(content)

      _other when attempts > 0 ->
        Process.sleep(20)
        await_file(path, attempts - 1)
    end
  end

  defp alive?(pid), do: match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

  test "stdin takes writes once by offset, closes, and a read waits for output", %{exec: exec, opts: opts} do
    assert :ok = Processes.start(exec, "in", "cat; echo end", Keyword.put(opts, :stdin, true))

    assert :ok = Processes.write(exec, "in", "ab\n", Keyword.put(opts, :offset, 0))
    # The same write sent again, as after a lost reply, lands once.
    assert :ok = Processes.write(exec, "in", "ab\n", Keyword.put(opts, :offset, 0))
    assert {:error, :offset_mismatch} = Processes.write(exec, "in", "c", Keyword.put(opts, :offset, 1))

    # Waits for the output instead of answering with nothing at once.
    assert {:ok, %{output: "ab\n", status: :running}} = Processes.read(exec, "in", 0, Keyword.put(opts, :wait, 5_000))

    # An empty write at the current offset still closes, as a retried close does.
    assert :ok = Processes.write(exec, "in", "", Keyword.merge(opts, offset: 3, close: true))
    assert {:error, :stdin_closed} = Processes.write(exec, "in", "x", opts)
    assert {:ok, %{output: "ab\nend\n", status: {:exited, 0}}} = await_status(exec, "in", 0, opts)
  end

  test "a process started without stdin reads an empty one and refuses writes", %{exec: exec, opts: opts} do
    assert :ok = Processes.start(exec, "no-in", "cat; echo end", opts)
    assert {:ok, %{output: "end\n", status: {:exited, 0}}} = await_status(exec, "no-in", 0, opts)
    assert {:error, :stdin_closed} = Processes.write(exec, "no-in", "x", opts)
  end
end

defmodule Condukt.Sandbox.ProcessesReadTest do
  # Reads need no setsid: the process directory is written here.
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.Processes

  @moduletag :tmp_dir

  test "output reads back byte for byte through an exec that answers text only", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "processes")
    dir = Path.join(root, Processes.dir_name("p"))
    File.mkdir_p!(dir)
    output = String.duplicate("€", 1_000) <> <<0xFF, 0>>
    File.write!(Path.join(dir, "output"), output)
    File.write!(Path.join(dir, "status"), "0\n")

    # Like Microsandbox's exec, which answers "" for output that is not UTF-8.
    exec = fn script ->
      {out, code} = System.cmd("bash", ["-c", script], stderr_to_stdout: true)
      {:ok, %{output: if(String.valid?(out), do: out, else: ""), exit_code: code}}
    end

    # Slices of 1001 bytes split the three-byte characters.
    read =
      Stream.unfold(0, fn
        offset when offset == byte_size(output) ->
          nil

        offset ->
          {:ok, %{output: slice, offset: next, status: {:exited, 0}}} =
            Processes.read(exec, "p", offset, root: root, max_bytes: 1_001)

          {slice, next}
      end)

    assert Enum.join(read) == output
  end
end
