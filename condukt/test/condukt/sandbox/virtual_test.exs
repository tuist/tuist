defmodule Condukt.Sandbox.VirtualTest do
  # Run serially: each test creates its own bashkit NIF Session with a
  # per-Session tokio runtime. Running them in parallel adds nothing
  # (sessions are independent already) and just multiplies the cost of
  # spinning up runtimes.
  use ExUnit.Case, async: false

  alias Condukt.Sandbox

  @moduletag :virtual_sandbox

  setup do
    {:ok, sandbox} = Sandbox.new(Sandbox.Virtual)
    on_exit(fn -> Sandbox.shutdown(sandbox) end)
    %{sandbox: sandbox}
  end

  describe "exec/3" do
    test "runs commands in the in-memory bash interpreter", %{sandbox: sandbox} do
      assert {:ok, %{output: out, exit_code: 0}} = Sandbox.exec(sandbox, "echo hello")
      assert String.contains?(out, "hello")
    end

    test "returns nonzero exit codes", %{sandbox: sandbox} do
      assert {:ok, %{exit_code: 7}} = Sandbox.exec(sandbox, "exit 7")
    end

    test "is stateless: cwd does not persist across exec calls", %{sandbox: sandbox} do
      _ = Sandbox.exec(sandbox, "mkdir -p /a/b && cd /a/b")
      assert {:ok, %{output: out}} = Sandbox.exec(sandbox, "pwd")
      refute String.contains?(out, "/a/b")
    end

    test "honors the per-call :cwd opt", %{sandbox: sandbox} do
      _ = Sandbox.exec(sandbox, "mkdir -p /work")
      assert {:ok, %{output: out}} = Sandbox.exec(sandbox, "pwd", cwd: "/work")
      assert String.trim(out) == "/work"
    end
  end

  describe "read/write/edit" do
    test "round-trips file content", %{sandbox: sandbox} do
      assert :ok = Sandbox.write(sandbox, "/tmp/foo.txt", "hi")
      assert {:ok, "hi"} = Sandbox.read(sandbox, "/tmp/foo.txt")
    end

    test "creates parent directories on write", %{sandbox: sandbox} do
      assert :ok = Sandbox.write(sandbox, "/a/b/c.txt", "deep")
      assert {:ok, "deep"} = Sandbox.read(sandbox, "/a/b/c.txt")
    end

    test "reports :enoent on missing files", %{sandbox: sandbox} do
      assert {:error, :enoent} = Sandbox.read(sandbox, "/nope.txt")
    end

    test "edits a unique occurrence", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/f.txt", "Hello, World!")
      assert {:ok, %{occurrences: 1, content: "Hello, Elixir!"}} = Sandbox.edit(sandbox, "/f.txt", "World", "Elixir")
      assert {:ok, "Hello, Elixir!"} = Sandbox.read(sandbox, "/f.txt")
    end

    test "reports zero/multiple occurrences without writing", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/f.txt", "foo bar foo")
      assert {:ok, %{occurrences: 0}} = Sandbox.edit(sandbox, "/f.txt", "missing", "x")
      assert {:ok, %{occurrences: 2}} = Sandbox.edit(sandbox, "/f.txt", "foo", "baz")
      assert {:ok, "foo bar foo"} = Sandbox.read(sandbox, "/f.txt")
    end
  end

  describe "glob/3" do
    test "lists matching paths", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/tmp/a.txt", "")
      :ok = Sandbox.write(sandbox, "/tmp/b.txt", "")
      :ok = Sandbox.write(sandbox, "/tmp/skip.md", "")

      assert {:ok, paths} = Sandbox.glob(sandbox, "/tmp/*.txt")
      assert Enum.sort(paths) == ["/tmp/a.txt", "/tmp/b.txt"]
    end

    test "returns [] when nothing matches", %{sandbox: sandbox} do
      assert {:ok, []} = Sandbox.glob(sandbox, "/nope/*.txt")
    end

    test "rejects unsafe glob patterns silently", %{sandbox: sandbox} do
      assert {:ok, []} = Sandbox.glob(sandbox, "/tmp/$(rm -rf /).txt")
    end
  end

  describe "grep/3" do
    test "finds matching lines with paths and line numbers", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/a.txt", "alpha\nneedle\ngamma")
      :ok = Sandbox.write(sandbox, "/b.txt", "delta\n")

      assert {:ok, [%{path: "/a.txt", line_number: 2, line: "needle"}]} =
               Sandbox.grep(sandbox, "needle")
    end

    test "filters by file glob", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/keep.ex", "needle")
      :ok = Sandbox.write(sandbox, "/skip.txt", "needle")

      assert {:ok, [%{path: "/keep.ex"}]} = Sandbox.grep(sandbox, "needle", glob: "*.ex")
    end

    test "honors case_sensitive: false", %{sandbox: sandbox} do
      :ok = Sandbox.write(sandbox, "/x.txt", "FOO\nfoo")
      assert {:ok, sensitive} = Sandbox.grep(sandbox, "foo")
      assert length(sensitive) == 1
      assert {:ok, insensitive} = Sandbox.grep(sandbox, "foo", case_sensitive: false)
      assert length(insensitive) == 2
    end
  end

  describe "mount/3" do
    @tag :tmp_dir
    test "mounts a host directory at runtime, exposing files inside the VFS", %{sandbox: sandbox, tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "host_file.txt"), "from host")
      assert :ok = Sandbox.mount(sandbox, tmp_dir, "/mnt")
      assert {:ok, "from host"} = Sandbox.read(sandbox, "/mnt/host_file.txt")
    end

    @tag :tmp_dir
    test "construction-time mount works the same way", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "bootstrap.txt"), "boot")
      {:ok, sb} = Sandbox.new(Sandbox.Virtual, mounts: [{tmp_dir, "/m", :readonly}])
      on_exit(fn -> Sandbox.shutdown(sb) end)

      assert {:ok, "boot"} = Sandbox.read(sb, "/m/bootstrap.txt")
    end
  end
end
