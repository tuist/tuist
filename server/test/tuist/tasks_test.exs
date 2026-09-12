defmodule Tuist.TasksTest do
  use ExUnit.Case, async: true

  alias Tuist.Tasks

  defmodule Query do
    def explode, do: raise("pool exhausted")
  end

  describe "parallel_tasks/2" do
    test "returns the results in the order the functions were given" do
      assert [1, 2, 3] = Tasks.parallel_tasks([fn -> 1 end, fn -> 2 end, fn -> 3 end])
    end

    test "reraises a task's exception with the task's stacktrace when the caller traps exits" do
      Process.flag(:trap_exit, true)

      {exception, stacktrace} =
        try do
          Tasks.parallel_tasks([fn -> :ok end, &Query.explode/0])
        rescue
          exception -> {exception, __STACKTRACE__}
        end

      assert %RuntimeError{message: "pool exhausted"} = exception
      assert Enum.any?(stacktrace, &match?({Query, :explode, 0, _}, &1))
    end

    test "reraises as soon as a task fails instead of waiting for its siblings" do
      Process.flag(:trap_exit, true)
      parent = self()

      queries = [
        fn -> raise "pool exhausted" end,
        fn ->
          send(parent, {:sibling, self()})
          Process.sleep(:infinity)
        end
      ]

      assert_raise RuntimeError, "pool exhausted", fn -> Tasks.parallel_tasks(queries) end

      assert_receive {:sibling, sibling}
      refute Process.alive?(sibling)
    end

    test "exits with the reason when a task exits without an exception" do
      Process.flag(:trap_exit, true)

      assert catch_exit(Tasks.parallel_tasks([fn -> exit(:boom) end])) == :boom
    end
  end
end
