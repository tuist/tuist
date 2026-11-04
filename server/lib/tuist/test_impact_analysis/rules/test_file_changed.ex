defmodule Tuist.TestImpactAnalysis.Rules.TestFileChanged do
  @moduledoc """
  Rule 2. Selects every test of each suite a changed test file belongs to,
  whether or not that test's own evidence includes the file. A test file is
  one the baseline recorded as test code; its suites are those whose tests'
  newest versions include it, which holds what the suite's setup executed.
  `matched_path` is the file, the first in path order when several match.
  A test outside any suite only selects itself.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :test_file_changed

  @impl true
  def decide(input, state) do
    tests = Map.new(input.tests, &{&1.test_case_id, &1})

    suites =
      for path <- Input.changed_paths(input),
          Input.test_file?(input, path),
          test_case_id <- input |> Input.tests_touching(path) |> Enum.sort(),
          test = tests[test_case_id],
          test != nil,
          reduce: %{} do
        acc -> Map.put_new(acc, suite(test), path)
      end

    state =
      Enum.reduce(State.undecided(state, input.tests), state, fn test, state ->
        case Map.get(suites, suite(test)) do
          nil -> state
          path -> State.select(state, test.test_case_id, name(), path)
        end
      end)

    {state, :continue}
  end

  defp suite(%{suite_name: "", test_case_id: test_case_id}), do: {:test, test_case_id}
  defp suite(%{module_name: module_name, suite_name: suite_name}), do: {:suite, module_name, suite_name}
end
