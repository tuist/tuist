defmodule Tuist.TestImpactAnalysis.Rules.NoEvidenceTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.NoEvidence
  alias Tuist.TestImpactAnalysis.State

  test "selects the tests without a version in the window" do
    input =
      input(
        tests: ["AppTests/CartTests/totalSumsItems()", "CoreTests/MoneyTests/testAdds"],
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m"})]}
      )

    {state, :continue} = NoEvidence.decide(input, State.new())

    assert state.decisions == %{
             "AppTests/CartTests/totalSumsItems()" => %{decision: :selected, reason: :no_evidence, matched_path: nil}
           }
  end

  test "selects them whatever changed" do
    input =
      input(
        tests: ["AppTests/CartTests/totalSumsItems()"],
        changed_files: [changed("README.md", affected_modules: [])]
      )

    {state, :continue} = NoEvidence.decide(input, State.new())
    assert Map.keys(state.decisions) == ["AppTests/CartTests/totalSumsItems()"]
  end

  test "leaves decided tests alone" do
    input = input(tests: ["AppTests/CartTests/totalSumsItems()"])
    state = State.select(State.new(), "AppTests/CartTests/totalSumsItems()", :earlier)

    assert NoEvidence.decide(input, state) == {state, :continue}
  end
end
