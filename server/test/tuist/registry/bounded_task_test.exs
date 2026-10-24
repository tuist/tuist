defmodule Tuist.Registry.BoundedTaskTest do
  use ExUnit.Case, async: true

  alias Tuist.Registry.BoundedTask

  test "a task exception does not terminate its caller or retain its supervisor" do
    parent = self()

    assert {:exit, {%RuntimeError{message: "synthetic failure"}, _}} =
             BoundedTask.run(
               fn ->
                 {:links, [supervisor]} = Process.info(self(), :links)
                 send(parent, {:child, self(), supervisor})
                 raise "synthetic failure"
               end,
               5_000
             )

    assert_receive {:child, task, supervisor}
    refute Process.alive?(task)
    refute Process.alive?(supervisor)
  end

  test "a timeout terminates the task and the anonymous supervisor" do
    parent = self()

    assert nil ==
             BoundedTask.run(
               fn ->
                 {:links, [supervisor]} = Process.info(self(), :links)
                 send(parent, {:child, self(), supervisor})
                 Process.sleep(:infinity)
               end,
               100
             )

    assert_receive {:child, task, supervisor}
    refute Process.alive?(task)
    refute Process.alive?(supervisor)
  end

  test "a killed caller terminates its task without waiting for the task timeout" do
    parent = self()

    {owner, owner_ref} =
      spawn_monitor(fn ->
        BoundedTask.run(
          fn ->
            {:links, [supervisor]} = Process.info(self(), :links)
            send(parent, {:child, self(), supervisor})
            Process.sleep(:infinity)
          end,
          30_000
        )
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:child, task, supervisor}

    on_exit(fn ->
      Process.exit(task, :kill)
      Process.exit(supervisor, :kill)
    end)

    task_ref = Process.monitor(task)
    supervisor_ref = Process.monitor(supervisor)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}
    assert_receive {:DOWN, ^task_ref, :process, ^task, :killed}, 5_000
    assert_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, :killed}, 5_000
  end
end
