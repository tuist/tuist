defmodule Tuist.TestImpactAnalysis.Rules.NoEvidence do
  @moduledoc """
  Rule 4. Selects the tests without a test-scoped version in the window: a
  new test or target, a test that ran without attribution (a target without
  TestCoverageAttribution, or any Swift Testing test), another platform, or
  evidence that expired. Targets whose hash matched never reach the server,
  so these are tests a default run would run too.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :no_evidence

  @impl true
  def decide(input, state) do
    state =
      state
      |> State.undecided(input.tests)
      |> Enum.filter(&is_nil(Input.evidence(input, &1.test_case_id)))
      |> Enum.reduce(state, &State.select(&2, &1.test_case_id, name()))

    {state, :continue}
  end
end
