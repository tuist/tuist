defmodule Tuist.TestImpactAnalysis.Rules.FailedLastRun do
  @moduledoc """
  Rule 3. Selects the tests whose newest version in the window failed, or
  comes from a run where they were flaky.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :failed_last_run

  @impl true
  def decide(input, state) do
    state =
      state
      |> State.undecided(input.tests)
      |> Enum.filter(&failed?(input, &1.test_case_id))
      |> Enum.reduce(state, &State.select(&2, &1.test_case_id, name()))

    {state, :continue}
  end

  defp failed?(input, test_case_id) do
    case Input.evidence(input, test_case_id) do
      %{newest: %{passed: passed}} -> passed not in [true, 1] or Input.flaky?(input, test_case_id)
      nil -> false
    end
  end
end
