defmodule Condukt.Tools.CommandTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Condukt.Tools.Command

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "executes a trusted command with structured arguments", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "git", ["status", "--short"], opts ->
      assert opts[:cd] == tmp_dir
      assert opts[:stderr_to_stdout] == true
      assert opts[:timeout] == 120_000
      assert {"TERM", "dumb"} in opts[:env]
      {"M README.md\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: [command: "git"]}
    {:ok, result} = Command.call(%{"args" => ["status", "--short"]}, context)

    assert String.contains?(result, "README.md")
  end

  test "injects trusted environment from tool options", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "gh", ["pr", "view"], opts ->
      assert opts[:cd] == tmp_dir
      assert {"GH_TOKEN", "secret-token"} in opts[:env]
      assert {"PAGER", "cat"} in opts[:env]
      {"#9\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: [command: "gh", env: [GH_TOKEN: "secret-token"]]}
    {:ok, result} = Command.call(%{"args" => ["pr", "view"]}, context)

    assert String.contains?(result, "#9")
  end

  test "injects session secrets alongside trusted tool environment", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "gh", ["api", "user"], opts ->
      assert opts[:cd] == tmp_dir
      assert {"GH_TOKEN", "session-token"} in opts[:env]
      assert {"EXTRA", "1"} in opts[:env]
      {"{}\n", 0}
    end)

    context = %{
      cwd: tmp_dir,
      opts: [command: "gh", env: [EXTRA: "1"]],
      secrets: %Condukt.Secrets{env: [{"GH_TOKEN", "session-token"}]}
    }

    {:ok, result} = Command.call(%{"args" => ["api", "user"]}, context)

    assert String.contains?(result, "{}")
  end

  test "accepts cwd relative to the agent cwd", %{tmp_dir: tmp_dir} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    MuonTrap
    |> expect(:cmd, fn "mix", ["test"], opts ->
      assert opts[:cd] == nested_dir
      {"1 test, 0 failures\n", 0}
    end)

    context = %{cwd: tmp_dir, opts: [command: "mix"]}
    {:ok, result} = Command.call(%{"args" => ["test"], "cwd" => "nested"}, context)

    assert String.contains?(result, "0 failures")
  end

  test "returns an error for invalid command arguments", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: [command: "git"]}

    assert {:error, "Command arguments must be an array of strings"} =
             Command.call(%{"args" => ["status", 1]}, context)
  end

  test "returns runner errors as command failures", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "git", ["status"], _opts ->
      raise ErlangError, original: :enoent
    end)

    context = %{cwd: tmp_dir, opts: [command: "git"]}

    assert {:error, "Command failed: Erlang error: :enoent"} =
             Command.call(%{"args" => ["status"]}, context)
  end
end
