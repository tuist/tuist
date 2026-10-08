defmodule TuistEx.Analytics.SubprocessTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Subprocess

  @moduletag :tmp_dir

  test "returns the exit status and passes the environment", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "env")
    sh = System.find_executable("sh")

    assert Subprocess.run(
             sh,
             ["-c", ~S|printf %s "$TUIST_EX_VALUE" > "$TUIST_EX_PATH"; exit 3|],
             [
               {"TUIST_EX_VALUE", "한글"},
               {"TUIST_EX_PATH", path}
             ]
           ) == 3

    assert File.read!(path) == "한글"
  end

  test "leaves the output of a character written in two parts intact" do
    # The command writes to the standard output of the VM that runs it, so
    # that VM is a separate one whose output is read back here.
    ebin = :code.which(Subprocess) |> List.to_string() |> Path.dirname()
    command = ~S|printf '\355\225'; sleep 0.1; printf '\234\n'|

    script = """
    status = TuistEx.Analytics.Subprocess.run(System.find_executable("sh"), ["-c", #{inspect(command)}], [])
    System.halt(status)
    """

    assert System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script]) == {"한\n", 0}
  end
end
