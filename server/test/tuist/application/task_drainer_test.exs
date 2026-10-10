defmodule Tuist.Application.TaskDrainerTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.TaskDrainer

  test "lets an active task finish before shutting down its supervisor" do
    name = String.to_atom("drain_tasks_#{System.unique_integer([:positive])}")

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Task.Supervisor, name: name},
          {TaskDrainer, supervisor: name, timeout: 1000}
        ],
        strategy: :one_for_one
      )

    parent = self()

    {:ok, task} =
      Task.Supervisor.start_child(name, fn ->
        send(parent, :started)

        receive do
          :finish -> send(parent, :finished)
        end
      end)

    assert_receive :started
    stopper = Task.async(fn -> Supervisor.stop(supervisor) end)
    assert Task.yield(stopper, 50) == nil
    assert Process.alive?(task)
    send(task, :finish)
    assert_receive :finished
    assert Task.await(stopper) == :ok
  end

  test "bounds shutdown when a task cannot finish" do
    name = String.to_atom("blocked_tasks_#{System.unique_integer([:positive])}")

    {:ok, supervisor} =
      Supervisor.start_link(
        [
          {Task.Supervisor, name: name},
          {TaskDrainer, supervisor: name, timeout: 10}
        ],
        strategy: :one_for_one
      )

    {:ok, task} = Task.Supervisor.start_child(name, fn -> Process.sleep(:infinity) end)
    ref = Process.monitor(task)
    stopper = Task.async(fn -> Supervisor.stop(supervisor) end)
    assert Task.await(stopper, 1000) == :ok
    assert_receive {:DOWN, ^ref, :process, ^task, :shutdown}
  end
end
