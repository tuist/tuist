defmodule Condukt.SandboxTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox

  defmodule MinimalSandbox do
    @behaviour Condukt.Sandbox

    @impl true
    def init(opts), do: {:ok, %{tag: opts[:tag]}}

    @impl true
    def shutdown(_state), do: :ok

    @impl true
    def read_file(state, path), do: {:ok, "#{state.tag}:#{path}"}

    @impl true
    def write_file(_state, _path, _content), do: :ok

    @impl true
    def edit_file(_state, _path, _old, _new), do: {:ok, %{occurrences: 1, content: ""}}

    @impl true
    def exec(_state, _command, _opts), do: {:ok, %{output: "ok", exit_code: 0}}

    @impl true
    def cwd(_state), do: "/"

    # Intentionally no glob/3, grep/3, mount/3 — they're optional callbacks.
  end

  test "new/2 returns {:ok, sandbox} when init succeeds" do
    assert {:ok, %Sandbox{} = sandbox} = Sandbox.new(MinimalSandbox, tag: "abc")
    assert {:ok, "abc:foo"} = Sandbox.read(sandbox, "foo")
  end

  test "resolve/1 accepts a struct, a module, or {module, opts}" do
    {:ok, %Sandbox{} = built} = Sandbox.new(MinimalSandbox, tag: "x")
    assert {:ok, ^built} = Sandbox.resolve(built)

    assert {:ok, %Sandbox{module: MinimalSandbox}} = Sandbox.resolve(MinimalSandbox)
    assert {:ok, %Sandbox{module: MinimalSandbox}} = Sandbox.resolve({MinimalSandbox, tag: "y"})
    assert {:error, {:invalid_sandbox, "not a sandbox"}} = Sandbox.resolve("not a sandbox")
  end

  test "glob/grep/mount return :not_supported when callback is missing" do
    {:ok, sandbox} = Sandbox.new(MinimalSandbox, tag: "x")
    assert {:error, :not_supported} = Sandbox.glob(sandbox, "*")
    assert {:error, :not_supported} = Sandbox.grep(sandbox, "x")
    assert {:error, :not_supported} = Sandbox.mount(sandbox, "/host", "/vfs")
  end
end
