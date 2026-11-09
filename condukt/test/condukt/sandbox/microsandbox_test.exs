defmodule Condukt.Sandbox.MicrosandboxTest do
  use ExUnit.Case, async: true

  alias Condukt.{Context, Sandbox}

  @moduletag :tmp_dir

  defmodule FakeNIF do
    def new_session(config) do
      send(self(), {:new_session, config})

      case Process.get({__MODULE__, :new_session}) do
        nil -> {:ok, :session}
        fun -> fun.(config)
      end
    end

    def shutdown(_session), do: :ok

    def exec(session, shell, command, cwd, env, timeout_ms) do
      fetch_handler!(:exec).(session, shell, command, cwd, env, timeout_ms)
    end

    def read_file(session, path) do
      fetch_handler!(:read_file).(session, path)
    end

    def write_file(session, path, content) do
      fetch_handler!(:write_file).(session, path, content)
    end

    defp fetch_handler!(name) do
      Process.get({__MODULE__, name}) ||
        raise "missing fake NIF handler for #{inspect(name)}"
    end
  end

  test "init/1 builds a session-scoped microsandbox config", %{tmp_dir: tmp_dir} do
    Process.put({FakeNIF, :new_session}, fn _config -> {:ok, :session} end)

    assert {:ok, %Sandbox{} = sandbox} =
             Sandbox.new(Sandbox.Microsandbox,
               id: "unit-test",
               workspace_host: tmp_dir,
               nif_module: FakeNIF
             )

    assert_received {:new_session, config}
    assert config.name == "condukt-unit-test"
    assert config.image == "ubuntu:24.04"
    assert config.cwd == "/workspace"
    assert config.shell == "/bin/bash"
    assert config.cpus == 2
    assert config.memory_mib == 1024
    assert config.env == []
    assert config.mounts == [%{host_path: tmp_dir, guest_path: "/workspace", mode: :readwrite}]
    assert Sandbox.cwd(sandbox) == "/workspace"
  end

  test "exec resolves relative cwd and forwards env and timeout", %{tmp_dir: tmp_dir} do
    sandbox = sandbox_handle(tmp_dir)

    Process.put({FakeNIF, :exec}, fn :session, "/bin/bash", "pwd", "/workspace/lib", env, 5_000 ->
      assert env == [{"FOO", "bar"}]
      {:ok, %{output: "/workspace/lib\n", exit_code: 0}}
    end)

    assert {:ok, %{output: "/workspace/lib\n", exit_code: 0}} =
             Sandbox.exec(sandbox, "pwd", cwd: "lib", env: [FOO: "bar"], timeout: 5_000)
  end

  test "read, write, and edit resolve guest paths through the NIF", %{tmp_dir: tmp_dir} do
    sandbox = sandbox_handle(tmp_dir)

    Process.put({FakeNIF, :read_file}, fn :session, path ->
      case path do
        "/workspace/lib/example.txt" -> {:ok, "hello world"}
        "/workspace/lib/edit.txt" -> {:ok, "hello world"}
      end
    end)

    Process.put({FakeNIF, :write_file}, fn :session, path, content ->
      send(self(), {:write_file, path, content})
      {:ok, :ok}
    end)

    assert {:ok, "hello world"} = Sandbox.read(sandbox, "lib/example.txt")
    assert :ok = Sandbox.write(sandbox, "lib/example.txt", "updated")
    assert_received {:write_file, "/workspace/lib/example.txt", "updated"}

    assert {:ok, %{occurrences: 1, content: "hello condukt"}} =
             Sandbox.edit(sandbox, "lib/edit.txt", "world", "condukt")

    assert_received {:write_file, "/workspace/lib/edit.txt", "hello condukt"}
  end

  test "glob and grep operate on the host-backed workspace mount", %{tmp_dir: tmp_dir} do
    sandbox = sandbox_handle(tmp_dir)

    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.write!(Path.join(tmp_dir, "lib/a.ex"), "alpha\nneedle\nomega")
    File.write!(Path.join(tmp_dir, "lib/b.ex"), "beta")

    assert {:ok, ["lib/a.ex", "lib/b.ex"]} = Sandbox.glob(sandbox, "lib/*.ex")

    assert {:ok, [%{path: "lib/a.ex", line_number: 2, line: "needle"}]} =
             Sandbox.grep(sandbox, "needle")
  end

  test "project instruction discovery works through mounted workspace reads", %{tmp_dir: tmp_dir} do
    sandbox = sandbox_handle(tmp_dir)

    File.write!(Path.join(tmp_dir, "AGENTS.md"), "Use the mounted workspace")
    File.mkdir_p!(Path.join(tmp_dir, ".agents/skills/demo"))

    File.write!(
      Path.join(tmp_dir, ".agents/skills/demo/SKILL.md"),
      """
      ---
      name: demo
      description: Demo skill
      ---
      """
    )

    Process.put({FakeNIF, :read_file}, fn :session, guest_path ->
      host_path = String.replace_prefix(guest_path, "/workspace", tmp_dir)
      File.read(host_path)
    end)

    context = Context.discover(sandbox)

    assert context.agents_md =~ "Use the mounted workspace"
    assert [%{name: "demo", path: ".agents/skills/demo/SKILL.md"}] = context.skills
  end

  defp sandbox_handle(tmp_dir) do
    Process.put({FakeNIF, :new_session}, fn _config -> {:ok, :session} end)

    {:ok, sandbox} =
      Sandbox.new(Sandbox.Microsandbox,
        id: "unit-test-#{System.unique_integer([:positive, :monotonic])}",
        workspace_host: tmp_dir,
        nif_module: FakeNIF
      )

    sandbox
  end
end
