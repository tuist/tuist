defmodule Condukt.Sandbox.LocalTest do
  # Run serially: the exec/3 tests spawn real bash subprocesses via
  # MuonTrap. Keeping this module synchronous avoids extra port contention
  # around the Linux runner's output-capture path.
  use ExUnit.Case, async: false

  alias Condukt.Sandbox

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{sandbox: sandbox}
  end

  describe "init/1" do
    test "defaults cwd to File.cwd!() when no :cwd is given" do
      {:ok, sandbox} = Sandbox.new(Sandbox.Local)
      assert sandbox.state.cwd == File.cwd!()
    end

    test "expands a relative cwd", %{tmp_dir: tmp_dir} do
      {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
      assert sandbox.state.cwd == Path.expand(tmp_dir)
    end
  end

  describe "read_file / write_file" do
    test "round-trips file content", %{sandbox: sandbox} do
      assert :ok = Sandbox.write(sandbox, "hello.txt", "hi")
      assert {:ok, "hi"} = Sandbox.read(sandbox, "hello.txt")
    end

    test "creates parent directories on write", %{sandbox: sandbox, tmp_dir: tmp_dir} do
      assert :ok = Sandbox.write(sandbox, "a/b/c.txt", "deep")
      assert File.read!(Path.join(tmp_dir, "a/b/c.txt")) == "deep"
    end

    test "returns :enoent for missing files", %{sandbox: sandbox} do
      assert {:error, :enoent} = Sandbox.read(sandbox, "nope.txt")
    end
  end

  describe "edit_file" do
    test "replaces a unique occurrence", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "f.txt", "Hello, World!")

      assert {:ok, %{occurrences: 1, content: "Hello, Elixir!"}} =
               Sandbox.edit(sandbox, "f.txt", "World", "Elixir")

      assert {:ok, "Hello, Elixir!"} = Sandbox.read(sandbox, "f.txt")
    end

    test "reports zero occurrences without writing", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "f.txt", "Hello")

      assert {:ok, %{occurrences: 0, content: "Hello"}} =
               Sandbox.edit(sandbox, "f.txt", "World", "Elixir")

      assert {:ok, "Hello"} = Sandbox.read(sandbox, "f.txt")
    end

    test "reports multiple occurrences without writing", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "f.txt", "foo bar foo")

      assert {:ok, %{occurrences: 2, content: "foo bar foo"}} =
               Sandbox.edit(sandbox, "f.txt", "foo", "baz")

      assert {:ok, "foo bar foo"} = Sandbox.read(sandbox, "f.txt")
    end
  end

  describe "exec/3" do
    test "runs a shell command and returns output + exit code", %{sandbox: sandbox} do
      assert {:ok, %{output: out, exit_code: 0}} = Sandbox.exec(sandbox, "echo hi")
      assert String.contains?(out, "hi")
    end

    test "returns nonzero exit codes", %{sandbox: sandbox} do
      assert {:ok, %{exit_code: 7}} = Sandbox.exec(sandbox, "exit 7")
    end

    test "respects per-call cwd opt", %{sandbox: sandbox, tmp_dir: tmp_dir} do
      nested = Path.join(tmp_dir, "nested")
      File.mkdir_p!(nested)

      assert {:ok, %{output: out}} = Sandbox.exec(sandbox, "pwd", cwd: "nested")
      assert String.trim(out) == nested
    end
  end

  describe "glob/3" do
    test "returns matching paths relative to cwd", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "a.ex", "")
      :ok = Sandbox.write(sandbox, "b.ex", "")
      :ok = Sandbox.write(sandbox, "skip.txt", "")

      assert {:ok, paths} = Sandbox.glob(sandbox, "*.ex")
      assert Enum.sort(paths) == ["a.ex", "b.ex"]
    end

    test "honors :limit", %{sandbox: sandbox} do
      for n <- 1..5, do: :ok = Sandbox.write(sandbox, "f#{n}.txt", "")
      assert {:ok, paths} = Sandbox.glob(sandbox, "*.txt", limit: 2)
      assert length(paths) == 2
    end
  end

  describe "grep/3" do
    test "returns matching lines with paths and line numbers", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "a.ex", "alpha\nbeta\ngamma")
      :ok = Sandbox.write(sandbox, "b.ex", "delta\nbeta\n")

      assert {:ok, matches} = Sandbox.grep(sandbox, "beta")
      paths = matches |> Enum.map(& &1.path) |> Enum.sort()
      assert paths == ["a.ex", "b.ex"]
      assert Enum.all?(matches, &(&1.line == "beta"))
    end

    test "honors :glob", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "keep.ex", "needle")
      :ok = Sandbox.write(sandbox, "skip.txt", "needle")

      assert {:ok, matches} = Sandbox.grep(sandbox, "needle", glob: "*.ex")
      assert Enum.map(matches, & &1.path) == ["keep.ex"]
    end

    test "honors case_sensitive: false", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "x.txt", "FOO\nfoo")

      assert {:ok, sensitive} = Sandbox.grep(sandbox, "foo")
      assert length(sensitive) == 1

      assert {:ok, insensitive} = Sandbox.grep(sandbox, "foo", case_sensitive: false)
      assert length(insensitive) == 2
    end

    test "returns invalid_regex for malformed patterns", %{sandbox: sandbox} do
      assert {:error, {:invalid_regex, _, _}} = Sandbox.grep(sandbox, "[")
    end
  end

  describe "processes" do
    setup %{tmp_dir: tmp_dir} do
      {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"))
      %{sandbox: sandbox}
    end

    test "a process outlives the process that started it and is found again by its id",
         %{sandbox: sandbox, tmp_dir: tmp_dir} do
      gate = Path.join(tmp_dir, "gate")
      command = "echo one; while [ ! -e gate ]; do sleep 0.05; done; echo two >&2; exit 3"

      starter = Task.async(fn -> Sandbox.start_process(sandbox, "p1", command, env: [{"X", "1"}]) end)
      assert :ok = Task.await(starter)

      assert {:ok, %{output: "one\n", status: :running}} = await_output(sandbox, "p1", "one\n")
      assert {:error, :already_started} = Sandbox.start_process(sandbox, "p1", command)

      File.touch!(gate)

      assert {:ok, %{output: "one\ntwo\n", offset: 8, size: 8, status: {:exited, 3}}} = await_exit(sandbox, "p1")
      assert {:ok, %{output: "ne", offset: 3}} = Sandbox.read_process(sandbox, "p1", 1, max_bytes: 2)
      assert {:error, :already_started} = Sandbox.start_process(sandbox, "p1", command)
    end

    test "reports a timeout, and stop kills a running command and forgets it", %{sandbox: sandbox, tmp_dir: tmp_dir} do
      assert :ok = Sandbox.start_process(sandbox, "slow", "sleep 5", timeout: 100)
      assert {:ok, %{status: :timeout}} = await_exit(sandbox, "slow")

      assert :ok = Sandbox.start_process(sandbox, "long", "echo $$ > pid; sleep 60")
      pid = await_file(Path.join(tmp_dir, "pid"))

      assert :ok = Sandbox.stop_process(sandbox, "long")
      assert {:error, :not_found} = Sandbox.read_process(sandbox, "long", 0)
      refute match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))

      assert :ok = Sandbox.stop_process(sandbox, "never-started")
      assert {:error, :not_found} = Sandbox.read_process(sandbox, "never-started", 0)
    end
  end

  defp await_output(sandbox, id, expected, attempts \\ 100) do
    case Sandbox.read_process(sandbox, id, 0) do
      {:ok, %{output: ^expected}} = result ->
        result

      _other when attempts > 0 ->
        Process.sleep(20)
        await_output(sandbox, id, expected, attempts - 1)
    end
  end

  defp await_exit(sandbox, id, attempts \\ 200) do
    case Sandbox.read_process(sandbox, id, 0) do
      {:ok, %{status: :running}} when attempts > 0 ->
        Process.sleep(20)
        await_exit(sandbox, id, attempts - 1)

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

  describe "mount/3" do
    test "is unsupported on Local", %{sandbox: sandbox} do
      assert {:error, :not_supported} = Sandbox.mount(sandbox, "/host", "/vfs")
    end
  end
end
