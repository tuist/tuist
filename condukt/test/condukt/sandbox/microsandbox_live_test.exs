defmodule Condukt.Sandbox.MicrosandboxLiveTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox

  @moduletag :tmp_dir
  @moduletag :microsandbox_sandbox

  setup %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "host.txt"), "host file\n")

    assert {:ok, %Sandbox{} = sandbox} =
             Sandbox.new(Sandbox.Microsandbox,
               id: "live-test-#{System.unique_integer([:positive, :monotonic])}",
               workspace_host: tmp_dir,
               image: "ubuntu:24.04"
             )

    on_exit(fn -> Sandbox.shutdown(sandbox) end)

    {:ok, sandbox: sandbox}
  end

  test "boots a live microsandbox and operates on the mounted workspace", %{sandbox: sandbox} do
    assert {:ok, %{output: output, exit_code: 0}} =
             Sandbox.exec(
               sandbox,
               "pwd && ls -1 && cat host.txt && echo guest > guest.txt && cat guest.txt",
               timeout: 120_000
             )

    assert output =~ "/workspace"
    assert output =~ "host.txt"
    assert output =~ "host file"
    assert output =~ "guest"

    assert {:ok, "guest\n"} = Sandbox.read(sandbox, "guest.txt")
    assert :ok = Sandbox.write(sandbox, "written.txt", "from write\n")
    assert {:ok, "from write\n"} = Sandbox.read(sandbox, "written.txt")
    assert {:ok, ["guest.txt", "host.txt", "written.txt"]} = Sandbox.glob(sandbox, "*.txt")

    assert {:ok, matches} = Sandbox.grep(sandbox, "guest|write", glob: "*.txt", limit: 20)

    assert %{path: "guest.txt", line_number: 1, line: "guest"} in matches
    assert %{path: "written.txt", line_number: 1, line: "from write"} in matches
  end
end
