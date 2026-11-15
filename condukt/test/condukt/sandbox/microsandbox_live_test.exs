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

  test "runs a process in the guest apart from the exec that started it", %{sandbox: sandbox} do
    assert :ok = Sandbox.start_process(sandbox, "p1", "echo one; sleep 1; echo two; exit 3")
    assert {:error, :already_started} = Sandbox.start_process(sandbox, "p1", "true")
    assert {:ok, %{status: :running}} = Sandbox.read_process(sandbox, "p1", 0)

    assert {:ok, %{output: "one\ntwo\n", status: {:exited, 3}}} = await_exit(sandbox, "p1")
    assert :ok = Sandbox.stop_process(sandbox, "p1")
    assert {:error, :not_found} = Sandbox.read_process(sandbox, "p1", 0)
  end

  defp await_exit(sandbox, id, attempts \\ 50) do
    case Sandbox.read_process(sandbox, id, 0) do
      {:ok, %{status: :running}} when attempts > 0 ->
        Process.sleep(200)
        await_exit(sandbox, id, attempts - 1)

      result ->
        result
    end
  end
end
