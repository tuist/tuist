defmodule Tuist.TestImpactAnalysis.Rules.OwnedWithoutEvidence do
  @moduledoc """
  Rule 6. Selects every test in the affected modules of each changed file no
  evidence includes: a resource, an asset catalog, a new file, or a file with
  only declarations. The client resolves the modules from its project graph:
  the test modules that depend, directly or not, on the file's owning
  target. A file no target owns (empty `affected_modules`) selects nothing,
  and neither does one the client couldn't classify (nil): project-level
  files the graph can't attribute are tracked files instead.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.State

  @impl true
  def name, do: :owned_without_evidence

  @impl true
  def decide(input, state) do
    modules =
      input.changed_files
      |> Enum.reject(&Input.evidenced?(input, &1.path))
      |> Enum.flat_map(&(Map.get(&1, :affected_modules) || []))
      |> Enum.uniq()

    state =
      state
      |> State.undecided(Input.tests_in_modules(input, modules))
      |> Enum.reduce(state, &State.select(&2, &1.test_case_id, name()))

    {state, :continue}
  end
end
