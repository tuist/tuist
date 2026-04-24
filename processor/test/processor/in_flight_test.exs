defmodule Processor.InFlightTest do
  use ExUnit.Case, async: false

  test "count starts at zero" do
    assert Processor.InFlight.count() == 0
  end

  test "track/1 increments the counter during execution and decrements after" do
    parent = self()

    task =
      Task.async(fn ->
        Processor.InFlight.track(fn ->
          send(parent, {:inside, Processor.InFlight.count()})
          receive do: (:go -> :ok)
          :result
        end)
      end)

    assert_receive {:inside, 1}
    send(task.pid, :go)
    assert Task.await(task) == :result
    assert Processor.InFlight.count() == 0
  end

  test "track/1 decrements even when the function raises" do
    assert_raise RuntimeError, fn ->
      Processor.InFlight.track(fn -> raise "boom" end)
    end

    assert Processor.InFlight.count() == 0
  end
end
