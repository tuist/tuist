defmodule Tuist.TestImpactAnalysis.Rules.Impacted do
  @moduledoc """
  Rule 5. Selects the tests the checkout reproduces none of their versions in
  the window for: a file the test or its suite's setup executed has a
  different blob now. Also selects every test of a module whose target-level
  evidence (what its test processes executed outside any test, such as an
  app's launch) includes a changed path.

  `matched_path` is the first changed path, in path order, that the test's
  newest version or its module's target-level evidence includes; nil when
  the version executed a file whose blob the checkout doesn't know without
  the diff naming it.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :impacted

  @impl true
  def decide(input, state) do
    state =
      state
      |> State.undecided(input.tests)
      |> Enum.reduce(state, fn test, state ->
        case Input.evidence(input, test.test_case_id) do
          nil -> state
          evidence -> decide_test(input, state, test, evidence)
        end
      end)

    {state, :continue}
  end

  defp decide_test(input, state, test, %{newest: newest, reproduced: reproduced}) do
    target_paths = Input.changed_target_paths(input, test.module_name)

    if is_nil(reproduced) or target_paths != [] do
      matched_path =
        newest.paths |> Enum.filter(&Input.changed?(input, &1)) |> Enum.concat(target_paths) |> Enum.min(fn -> nil end)

      State.select(state, test.test_case_id, name(), matched_path)
    else
      state
    end
  end
end
