defmodule TuistEx.LockTest do
  use ExUnit.Case, async: true

  test "serializes callers and removes the lock after the action" do
    directory =
      Path.join(System.tmp_dir!(), "tuist-ex-lock-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "token.lock")
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, counter} = Agent.start_link(fn -> {0, 0} end)

    action = fn ->
      Agent.update(counter, fn {active, maximum} -> {active + 1, max(maximum, active + 1)} end)
      Process.sleep(50)
      Agent.update(counter, fn {active, maximum} -> {active - 1, maximum} end)
    end

    tasks = for _ <- 1..4, do: Task.async(fn -> TuistEx.Lock.with_lock(path, action) end)
    Enum.each(tasks, &Task.await/1)

    assert Agent.get(counter, & &1) == {0, 1}
    refute File.exists?(path)
  end

  test "stops the heartbeat when the lock holder dies" do
    directory =
      Path.join(System.tmp_dir!(), "tuist-ex-lock-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "token.lock")
    on_exit(fn -> File.rm_rf(directory) end)
    parent = self()

    {:ok, holder} =
      Task.start(fn ->
        TuistEx.Lock.with_lock(path, fn ->
          send(parent, :locked)
          Process.sleep(:infinity)
        end)
      end)

    assert_receive :locked
    monitor = Process.monitor(holder)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^holder, :killed}

    {:ok, before} = File.stat(path, time: :posix)
    Process.sleep(2_500)
    {:ok, after_death} = File.stat(path, time: :posix)
    assert after_death.mtime == before.mtime
  end

  test "recovers a stale cleanup guard and stale lock" do
    directory =
      Path.join(System.tmp_dir!(), "tuist-ex-lock-#{System.unique_integer([:positive])}")

    path = Path.join(directory, "token.lock")
    on_exit(fn -> File.rm_rf(directory) end)
    File.mkdir_p!(directory)
    File.write!(path, "abandoned")
    File.write!(path <> ".reap", "abandoned")
    old_time = {{2000, 1, 1}, {0, 0, 0}}
    File.touch!(path, old_time)
    File.touch!(path <> ".reap", old_time)

    assert :ok = TuistEx.Lock.with_lock(path, fn -> :ok end)
    refute File.exists?(path)
    refute File.exists?(path <> ".reap")
  end
end
