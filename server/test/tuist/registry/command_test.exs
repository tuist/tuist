defmodule Tuist.Registry.CommandTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry.BoundedTask
  alias Tuist.Registry.Command
  alias Tuist.Registry.Temporary

  setup :set_mimic_from_context

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

  test "a command task exception returns a sanitized parent exception" do
    expect(System, :cmd, fn _, _, _ -> raise "synthetic sensitive child failure" end)

    assert_raise RuntimeError, "registry command process failed", fn ->
      Command.run("sh", ["-c", "printf partial-output"])
    end
  end

  @tag :tmp_dir
  test "killing a nested owner terminates its operating-system command", %{tmp_dir: directory} do
    pid_file = Path.join(directory, "command.pid")
    parent = self()

    {owner, ref} =
      spawn_monitor(fn ->
        BoundedTask.run(
          fn ->
            send(parent, {:nested_task, self()})

            Command.run("sh", ["-c", ~s(echo $$ > "$1"; exec sleep 30), "registry-command-test", pid_file],
              timeout: 10_000
            )
          end,
          15_000
        )
      end)

    assert_receive {:nested_task, nested_task}

    on_exit(fn ->
      Process.exit(owner, :kill)
      Process.exit(nested_task, :kill)
    end)

    assert await_file(pid_file, 300)
    pid = pid_file |> File.read!() |> String.trim() |> String.to_integer()
    assert pid > 0
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}
    assert await_process_exit(pid, 300)
  end

  defp await_file(_path, 0), do: false

  defp await_file(path, attempts) do
    if File.exists?(path) and File.read!(path) != "",
      do: true,
      else:
        (
          Process.sleep(10)
          await_file(path, attempts - 1)
        )
  end

  defp await_process_exit(_pid, 0), do: false

  defp await_process_exit(pid, attempts) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        await_process_exit(pid, attempts - 1)

      _ ->
        true
    end
  end

  test "a stalled child is bounded" do
    started = System.monotonic_time(:millisecond)
    assert {_, :timeout} = Command.run("sh", ["-c", "sleep 30"], timeout: 25)
    assert System.monotonic_time(:millisecond) - started < 2_000
  end
end
