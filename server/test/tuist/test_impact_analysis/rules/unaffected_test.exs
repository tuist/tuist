defmodule Tuist.TestImpactAnalysis.Rules.UnaffectedTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.Unaffected
  alias Tuist.TestImpactAnalysis.State

  test "skips every undecided test and ends the pipeline" do
    input = input(tests: ["CoreTests/MoneyTests/testAdds", "CoreTests/MoneyTests/testFormats"])
    state = State.select(State.new(), "CoreTests/MoneyTests/testAdds", :impacted, "Core/Money.swift")

    assert {state, :done} = Unaffected.decide(input, state)

    assert state.decisions == %{
             "CoreTests/MoneyTests/testAdds" => %{
               decision: :selected,
               reason: :impacted,
               matched_path: "Core/Money.swift"
             },
             "CoreTests/MoneyTests/testFormats" => %{decision: :skipped, reason: :unaffected, matched_path: nil}
           }
  end
end
