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

  describe "mount/3" do
    test "is unsupported on Local", %{sandbox: sandbox} do
      assert {:error, :not_supported} = Sandbox.mount(sandbox, "/host", "/vfs")
    end
  end
end
