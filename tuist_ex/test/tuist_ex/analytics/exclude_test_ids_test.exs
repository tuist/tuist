defmodule TuistEx.Analytics.ExcludeTestIdsTest do
  use ExUnit.Case, async: true

  # ExUnit runs one suite per VM, and the patch swaps a module of ExUnit's
  # own, so the suites run in a VM of their own.
  defp run_script(script) do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end

  test "leaves out only the test with the given module and name" do
    output =
      run_script(~S"""
      alias TuistEx.Analytics.ExcludeTestIds

      :ok = ExcludeTestIds.install([{CartTest, :"test add/2 rejects nil"}])
      ExUnit.start(autorun: false, formatters: [], include: [:focus], exclude: [:test])

      defmodule Recorder do
        use GenServer
        def init(_), do: {:ok, nil}

        def handle_cast({:test_finished, test}, state) do
          send(:owner, {:finished, test.module, test.name, test.state})
          {:noreply, state}
        end

        def handle_cast(_event, state), do: {:noreply, state}
      end

      ExUnit.configure(formatters: [Recorder])

      for module <- [CartTest, OrderTest] do
        defmodule module do
          use ExUnit.Case

          describe "add/2" do
            # What `--only focus` selects, which does not bring an
            # excluded id back.
            @tag :focus
            test "rejects nil", do: :ok

            test "accepts zero", do: :ok
          end
        end
      end

      Process.register(self(), :owner)
      %{total: 4, excluded: 3, failures: 0} = ExUnit.run()

      states =
        for _ <- 1..4, into: %{} do
          receive do
            {:finished, module, name, state} -> {{module, name}, state}
          end
        end

      {:excluded, "due to Tuist quarantine"} = states[{CartTest, :"test add/2 rejects nil"}]
      nil = states[{OrderTest, :"test add/2 rejects nil"}]
      {:excluded, "due to test filter"} = states[{CartTest, :"test add/2 accepts zero"}]
      {:excluded, "due to test filter"} = states[{OrderTest, :"test add/2 accepts zero"}]

      :ok = ExcludeTestIds.uninstall()
      false = ExcludeTestIds.installed?()
      :ok = ExUnit.Filters.eval([], [], %{module: CartTest, test: :"test add/2 rejects nil"}, [])
      IO.puts("exact exclusion verified")
      """)

    assert output =~ "exact exclusion verified"
  end

  test "keeps every other function of ExUnit.Filters" do
    output =
      run_script(~S"""
      alias TuistEx.Analytics.ExcludeTestIds

      :ok = ExcludeTestIds.install([])
      :ok = ExcludeTestIds.install([{CartTest, :"test ships"}])
      true = ExcludeTestIds.installed?()
      [slow: "true"] = ExUnit.Filters.parse(["slow:true"])
      {[:a], [:b]} = ExUnit.Filters.normalize([:a], [:b])
      ExUnit.Filters = ExUnit.Filters.__info__(:module)
      {:excluded, "due to b filter"} = ExUnit.Filters.eval([], [:b], %{b: true}, [])
      IO.puts("delegation verified")
      """)

    assert output =~ "delegation verified"
  end
end
