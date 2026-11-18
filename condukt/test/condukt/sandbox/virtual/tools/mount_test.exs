defmodule Condukt.Sandbox.Virtual.Tools.MountTest do
  use ExUnit.Case, async: false

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Virtual.Tools.Mount

  @moduletag :virtual_sandbox

  test "mounts a host directory and confirms the agent-visible path", %{} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Virtual)
    on_exit(fn -> Sandbox.shutdown(sandbox) end)

    tmp = System.tmp_dir!() |> Path.join("condukt_mount_tool_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "f.txt"), "x")

    {:ok, msg} =
      Mount.call(
        %{"host_path" => tmp, "vfs_path" => "/m"},
        %{sandbox: sandbox, opts: []}
      )

    assert msg =~ "Mounted #{tmp} at /m"
    assert {:ok, "x"} = Sandbox.read(sandbox, "/m/f.txt")

    File.rm_rf!(tmp)
  end

  test "returns a clear error against a sandbox that doesn't support mount" do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local)
    on_exit(fn -> Sandbox.shutdown(sandbox) end)

    {:error, msg} =
      Mount.call(
        %{"host_path" => "/anywhere", "vfs_path" => "/m"},
        %{sandbox: sandbox, opts: []}
      )

    assert msg =~ "does not support runtime mounting"
  end
end
