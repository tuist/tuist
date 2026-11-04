defmodule Tuist.TestImpactAnalysis.Rules.FailedLastRunTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.FailedLastRun
  alias Tuist.TestImpactAnalysis.State

  defp decide(input) do
    {state, :continue} = FailedLastRun.decide(input, State.new())
    state.decisions
  end

  test "selects tests whose reproduced version failed" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds", "CoreTests/MoneyTests/testFormats"],
        versions: %{
          "CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m"}, passed: false)],
          "CoreTests/MoneyTests/testFormats" => [version(%{"Core/Money.swift" => "m"})]
        }
      )

    assert decide(input) == %{
             "CoreTests/MoneyTests/testAdds" => %{decision: :selected, reason: :failed_last_run, matched_path: nil}
           }
  end

  test "reads the newest version the checkout reproduces" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds", "CoreTests/MoneyTests/testFormats"],
        baseline_blobs: %{"Core/Money.swift" => "m2"},
        versions: %{
          "CoreTests/MoneyTests/testAdds" => [
            version(%{"Core/Money.swift" => "m1"}, passed: false, ran_at: ~U[2026-11-01 00:00:00Z]),
            version(%{"Core/Money.swift" => "m2"}, ran_at: ~U[2026-11-02 00:00:00Z]),
            version(%{"Core/Money.swift" => "m3"}, passed: false, ran_at: ~U[2026-11-03 00:00:00Z])
          ],
          "CoreTests/MoneyTests/testFormats" => [
            version(%{"Core/Money.swift" => "m1"}, ran_at: ~U[2026-11-01 00:00:00Z]),
            version(%{"Core/Money.swift" => "m2"}, passed: false, ran_at: ~U[2026-11-02 00:00:00Z]),
            version(%{"Core/Money.swift" => "m3"}, ran_at: ~U[2026-11-03 00:00:00Z])
          ]
        }
      )

    assert Map.keys(decide(input)) == ["CoreTests/MoneyTests/testFormats"]
  end

  test "leaves a test the checkout reproduces no version of to later rules" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        baseline_blobs: %{"Core/Money.swift" => "m2"},
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m1"}, passed: false)]}
      )

    assert decide(input) == %{}
  end

  test "selects tests that were flaky in their reproduced version's run" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m"})]},
        flaky: ["CoreTests/MoneyTests/testAdds"]
      )

    assert %{"CoreTests/MoneyTests/testAdds" => %{reason: :failed_last_run}} = decide(input)
  end

  test "leaves tests without evidence to later rules" do
    assert decide(input(tests: ["AppTests/CartTests/totalSumsItems()"])) == %{}
  end
end
