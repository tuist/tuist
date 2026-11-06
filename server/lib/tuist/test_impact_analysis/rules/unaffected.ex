defmodule Tuist.TestImpactAnalysis.Rules.Unaffected do
  @moduledoc """
  Rule 7. Skips every test still undecided and ends the pipeline.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :unaffected

  @impl true
  def decide(input, state) do
    state =
      state
      |> State.undecided(input.tests)
      |> Enum.reduce(state, &State.skip(&2, &1.test_case_id, name()))

    {state, :done}
  end
end
