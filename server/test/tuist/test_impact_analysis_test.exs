defmodule Tuist.TestImpactAnalysisTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis
  alias Tuist.TestImpactAnalysis.Rules
  alias Tuist.TestImpactAnalysis.State

  defmodule SkipFirst do
    @moduledoc false
    def name, do: :skip_first
    def decide(input, state), do: {State.skip(state, hd(input.tests).test_case_id, :skip_first), :continue}
  end

  defmodule StopEarly do
    @moduledoc false
    def name, do: :stop_early
    def decide(_input, state), do: {state, :done}
  end

  @tests ["CoreTests/DiscountTests/testTenPercent", "CoreTests/MoneyTests/testAdds", "AppTests/CartTests/total()"]

  defp pipeline_input(changed_files) do
    input(
      tests: @tests,
      tracked_file_globs: ["**/*.xcconfig"],
      versions: %{
        "CoreTests/DiscountTests/testTenPercent" => [
          version(%{"Core/Discount.swift" => "d1", "Core/Money.swift" => "m1"})
        ],
        "CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m1"})]
      },
      changed_files: changed_files
    )
  end

  test "applies the rules in order and traces each" do
    result = TestImpactAnalysis.run(pipeline_input([changed("Core/Discount.swift")]))

    assert result.outcome == :selected
    assert result.rules_version == TestImpactAnalysis.rules_version()

    assert result.decisions == %{
             "CoreTests/DiscountTests/testTenPercent" => %{
               decision: :selected,
               reason: :impacted,
               matched_path: "Core/Discount.swift"
             },
             "CoreTests/MoneyTests/testAdds" => %{decision: :skipped, reason: :unaffected, matched_path: nil},
             "AppTests/CartTests/total()" => %{decision: :selected, reason: :no_evidence, matched_path: nil}
           }

    assert result.counts == %{requested: 3, selected: 2, skipped: 1}

    assert result.rule_trace == [
             %{rule: :tracked_files, selected: 0, skipped: 0, verdict: :continue},
             %{rule: :test_file_changed, selected: 0, skipped: 0, verdict: :continue},
             %{rule: :failed_last_run, selected: 0, skipped: 0, verdict: :continue},
             %{rule: :no_evidence, selected: 1, skipped: 0, verdict: :continue},
             %{rule: :impacted, selected: 1, skipped: 0, verdict: :continue},
             %{rule: :owned_without_evidence, selected: 0, skipped: 0, verdict: :continue},
             %{rule: :unaffected, selected: 0, skipped: 1, verdict: :done}
           ]
  end

  test "an abort discards every decision and falls back" do
    result =
      TestImpactAnalysis.run(pipeline_input([changed("Configs/Base.xcconfig")]), [
        Rules.NoEvidence | TestImpactAnalysis.rules()
      ])

    assert %{
             outcome: :fallback,
             reason: :tracked_file_changed,
             matched_path: "Configs/Base.xcconfig",
             decisions: %{},
             counts: %{requested: 3, selected: 0, skipped: 0}
           } = result

    assert result.rule_trace == [
             %{rule: :no_evidence, selected: 1, skipped: 0, verdict: :continue},
             %{rule: :tracked_files, selected: 0, skipped: 0, verdict: :abort}
           ]
  end

  test "tests left undecided when the pipeline stops run" do
    result = TestImpactAnalysis.run(pipeline_input([]), [SkipFirst, StopEarly, Rules.Unaffected])

    assert result.decisions == %{
             "CoreTests/DiscountTests/testTenPercent" => %{decision: :skipped, reason: :skip_first, matched_path: nil},
             "CoreTests/MoneyTests/testAdds" => %{decision: :selected, reason: :undecided, matched_path: nil},
             "AppTests/CartTests/total()" => %{decision: :selected, reason: :undecided, matched_path: nil}
           }

    assert Enum.map(result.rule_trace, & &1.rule) == [:skip_first, :stop_early]
  end

  test "tests left undecided when the rules run out run" do
    result = TestImpactAnalysis.run(pipeline_input([]), [Rules.NoEvidence])

    assert %{
             "CoreTests/MoneyTests/testAdds" => %{reason: :undecided},
             "AppTests/CartTests/total()" => %{reason: :no_evidence}
           } = result.decisions
  end

  test "selects nothing and skips nothing without tests in scope" do
    result = TestImpactAnalysis.run(input(tests: [], changed_files: [changed("Core/Money.swift")]))
    assert %{outcome: :selected, decisions: %{}, counts: %{requested: 0, selected: 0, skipped: 0}} = result
  end
end
