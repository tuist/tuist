defmodule Tuist.TestImpactAnalysis.Rules.OwnedWithoutEvidenceTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.OwnedWithoutEvidence
  alias Tuist.TestImpactAnalysis.State

  @tests ["CoreTests/MoneyTests/testAdds", "CatalogTests/LoadingTests/testCount", "AppUITests/ShopUITests/testShows"]

  defp decide(input) do
    {state, :continue} = OwnedWithoutEvidence.decide(input, State.new())
    state.decisions
  end

  test "selects every test in the affected modules of a file no evidence includes" do
    input =
      input(
        tests: @tests,
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m"})]},
        changed_files: [changed("Catalog/products.json", affected_modules: ["CatalogTests", "AppUITests"])]
      )

    assert decide(input) == %{
             "CatalogTests/LoadingTests/testCount" => %{
               decision: :selected,
               reason: :owned_without_evidence,
               matched_path: nil
             },
             "AppUITests/ShopUITests/testShows" => %{
               decision: :selected,
               reason: :owned_without_evidence,
               matched_path: nil
             }
           }
  end

  test "ignores files some evidence includes" do
    input =
      input(
        tests: @tests,
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m"})]},
        target_evidence: %{"AppTests" => ["App/Launch.swift"]},
        evidence_paths: ["Catalog/Search.swift"],
        changed_files: [
          changed("Core/Money.swift", affected_modules: ["CoreTests"]),
          changed("App/Launch.swift", affected_modules: ["AppUITests"]),
          changed("Catalog/Search.swift", affected_modules: ["CatalogTests"])
        ]
      )

    assert decide(input) == %{}
  end

  test "selects nothing for unowned or unclassified files" do
    input =
      input(
        tests: @tests,
        changed_files: [changed("README.md", affected_modules: []), changed("Configs/Shared.yml")]
      )

    assert decide(input) == %{}
  end
end
