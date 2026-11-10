defmodule Condukt.Tools.BashTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Condukt.Sandbox
  alias Condukt.Tools.Bash

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
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
