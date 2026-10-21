defmodule Tuist.Registry.CommandTest do
  use ExUnit.Case, async: true

  alias Tuist.Registry.Command
  alias Tuist.Registry.Temporary

  test "short commands preserve output and exit status without the port acknowledgement race" do
    for _ <- 1..40 do
      assert {"hello", 0} = Command.run("sh", ["-c", "printf hello"], timeout: 1_000)
    end

    assert {"failure\n", 3} =
             Command.run("sh", ["-c", "echo failure >&2; exit 3"], stderr_to_stdout: true, timeout: 1_000)
  end

  test "a killed owner cleans its private directory without blocking other jobs" do
    parent = self()

    task =
      Task.async(fn ->
        Temporary.with_directory(fn path ->
          File.write!(Path.join(path, "child"), "data")
          send(parent, {:directory, path})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:directory, directory}
    Task.shutdown(task, :brutal_kill)
    Process.sleep(100)
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "late-child"), "recreated while exiting")
    assert await_removed(directory, 300)
    assert {"ok", 0} = Command.run("sh", ["-c", "printf ok"], timeout: 1_000)
  end

  test "cleanup retries after normal return when a terminating child recreates entries" do
    directory = Temporary.with_directory(fn path -> path end)
    Process.sleep(100)
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "late-child"), "recreated while exiting")
    assert await_removed(directory, 300)
  end

  defp await_removed(_path, 0), do: false

  defp await_removed(path, attempts) do
    if File.exists?(path),
      do:
        (
          Process.sleep(10)
          await_removed(path, attempts - 1)
        ),
      else: true
  end

  test "a stalled child is bounded" do
    started = System.monotonic_time(:millisecond)
    assert {_, :timeout} = Command.run("sh", ["-c", "sleep 30"], timeout: 25)
    assert System.monotonic_time(:millisecond) - started < 2_000
  end
end
