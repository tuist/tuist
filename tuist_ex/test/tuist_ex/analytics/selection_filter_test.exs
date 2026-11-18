defmodule TuistEx.Analytics.SelectionFilterTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.ExUnitPatch

  @tests ~S"""
  defmodule CartTest do
    use ExUnit.Case

    describe "add/2" do
      test "same name", do: :ok
      test "kept", do: :ok
    end

    test "same name", do: :ok

    for index <- 1..3 do
      test "generated #{index}", do: :ok
    end

    @tag :skip
    test "tagged skip", do: :ok

    @tag :slow
    test "slow", do: :ok

    test "added by the change", do: :ok
  end

  defmodule PairOneTest do
    use ExUnit.Case, async: true
    test "returns ok", do: :ok
  end

  defmodule PairTwoTest do
    use ExUnit.Case, async: true
    test "returns ok", do: :ok
  end

  defmodule UnselectedTest do
    use ExUnit.Case, async: true

    setup_all do
      send(:selection_runner, :setup_all)
      :ok
    end

    test "anything", do: :ok
  end
  """

  @skipped [
    %{module: "CartTest", suite: "add/2", name: "same name"},
    %{module: "CartTest", suite: "", name: "generated 2"},
    %{module: "CartTest", suite: "", name: "tagged skip"},
    %{module: "CartTest", suite: "", name: "slow"},
    %{module: "PairTwoTest", suite: "", name: "returns ok"},
    %{module: "UnselectedTest", suite: "", name: nil},
    %{module: "GoneTest", suite: "", name: nil}
  ]

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "tuist-ex-selection-filter-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "cart_test.exs"), @tests)
    %{dir: dir}
  end

  # Runs the tests in a VM of their own, since the filter replaces that VM's
  # ExUnit, and prints each test's state as formatters see it.
  defp run(dir, ex_unit_config) do
    script = """
    defmodule Spy do
      use GenServer
      def init(_opts), do: {:ok, nil}

      def handle_cast({:test_finished, test}, state) do
        send(:selection_runner, {:state, inspect(test.module), test.name, test.state})
        {:noreply, state}
      end

      def handle_cast(_event, state), do: {:noreply, state}
    end

    Process.register(self(), :selection_runner)
    :ok = TuistEx.Analytics.SelectionFilter.apply(#{inspect(@skipped)})
    ExUnit.start(autorun: false, formatters: [Spy])
    ExUnit.configure(#{inspect(ex_unit_config)})
    Code.require_file(#{inspect(Path.join(dir, "cart_test.exs"))})
    ExUnit.run()

    messages = Stream.repeatedly(fn -> receive do m -> m after 0 -> nil end end) |> Enum.take_while(& &1)
    IO.puts("RESULT " <> inspect(Enum.sort(messages), limit: :infinity))
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, 0} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    [_, result] = String.split(output, "RESULT ", parts: 2)
    {result, []} = Code.eval_string(result)
    result
  end

  test "leaves out exactly the tests and modules a skip list names", %{dir: dir} do
    unselected = {:excluded, "due to tuist_unselected filter"}

    assert run(dir, exclude: [:slow]) == [
             {:state, "CartTest", :"test add/2 kept", nil},
             # Another describe's test of the same name runs.
             {:state, "CartTest", :"test add/2 same name", unselected},
             {:state, "CartTest", :"test added by the change", nil},
             {:state, "CartTest", :"test generated 1", nil},
             {:state, "CartTest", :"test generated 2", unselected},
             {:state, "CartTest", :"test generated 3", nil},
             {:state, "CartTest", :"test same name", nil},
             # What ExUnit leaves out itself keeps its own reason: neither
             # `@tag :skip` nor another filter is selection.
             {:state, "CartTest", :"test slow", {:excluded, "due to slow filter"}},
             {:state, "CartTest", :"test tagged skip", {:skipped, "due to skip tag"}},
             # The same name in another module of the file runs.
             {:state, "PairOneTest", :"test returns ok", nil},
             {:state, "PairTwoTest", :"test returns ok", unselected},
             # A module with nothing selected doesn't run its `setup_all`.
             {:state, "UnselectedTest", :"test anything", unselected}
           ]
  end

  test "runs a listed test an include filter picks, as for any exclusion", %{dir: dir} do
    states = run(dir, include: [describe: "add/2"], exclude: [:test])

    assert {:state, "CartTest", :"test add/2 same name", nil} in states
    assert {:state, "CartTest", :"test add/2 kept", nil} in states
    assert {:state, "CartTest", :"test same name", {:excluded, "due to test filter"}} in states
  end

  test "doesn't replace a module that works in a way it doesn't know" do
    assert ExUnitPatch.wrap(
             ExUnit.Filters,
             TuistEx.Analytics.SelectionFilterTest.Never,
             :__never__,
             [eval: 5],
             quote(do: nil)
           ) == :error

    refute function_exported?(ExUnit.Filters, :__never__, 0)
  end
end
