defmodule Tuist.TestImpactAnalysis.Rules.ImpactedTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.Impacted
  alias Tuist.TestImpactAnalysis.State

  defp decide(input) do
    {state, :continue} = Impacted.decide(input, State.new())
    state.decisions
  end

  test "selects tests that executed a changed file, with the first changed path" do
    input =
      input(
        tests: ["CoreTests/DiscountTests/testTenPercent", "CoreTests/MoneyTests/testAdds"],
        versions: %{
          "CoreTests/DiscountTests/testTenPercent" => [
            version(%{"Core/Discount.swift" => "d1", "Core/Money.swift" => "m1", "Core/Tax.swift" => "t1"})
          ],
          "CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m1"})]
        },
        changed_files: [changed("Core/Tax.swift"), changed("Core/Discount.swift")]
      )

    assert decide(input) == %{
             "CoreTests/DiscountTests/testTenPercent" => %{
               decision: :selected,
               reason: :impacted,
               matched_path: "Core/Discount.swift"
             }
           }
  end

  test "leaves a test whose newer version the checkout reproduces" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        versions: %{
          "CoreTests/MoneyTests/testAdds" => [
            version(%{"Core/Money.swift" => "m1"}, ran_at: ~U[2026-11-01 00:00:00Z]),
            version(%{"Core/Money.swift" => "m2"}, sha: "later", ran_at: ~U[2026-11-02 00:00:00Z])
          ]
        },
        changed_files: [changed("Core/Money.swift", blob: "m2")]
      )

    assert decide(input) == %{}
  end

  test "selects a test whose evidence lost a file" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m1"})]},
        changed_files: [changed("Core/Money.swift", status: "D", blob: nil)]
      )

    assert %{"CoreTests/MoneyTests/testAdds" => %{matched_path: "Core/Money.swift"}} = decide(input)
  end

  test "selects every test of a module whose target-level evidence changed" do
    input =
      input(
        tests: ["CatalogTests/LoadingTests/testCount", "CatalogTests/SearchTests/matchesName()"],
        versions: %{
          "CatalogTests/LoadingTests/testCount" => [version(%{"Catalog/Catalog.swift" => "c1"})],
          "CatalogTests/SearchTests/matchesName()" => [version(%{"Catalog/Catalog.swift" => "c1"})]
        },
        target_evidence: %{"CatalogTests" => ["Catalog/Search.swift", "Catalog/Launch.swift"]},
        changed_files: [changed("Catalog/Search.swift")]
      )

    assert decide(input) == %{
             "CatalogTests/LoadingTests/testCount" => %{
               decision: :selected,
               reason: :impacted,
               matched_path: "Catalog/Search.swift"
             },
             "CatalogTests/SearchTests/matchesName()" => %{
               decision: :selected,
               reason: :impacted,
               matched_path: "Catalog/Search.swift"
             }
           }
  end

  test "ignores another module's target-level evidence" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        versions: %{"CoreTests/MoneyTests/testAdds" => [version(%{"Core/Money.swift" => "m1"})]},
        target_evidence: %{"AppTests" => ["Core/Discount.swift"]},
        changed_files: [changed("Core/Discount.swift")]
      )

    assert decide(input) == %{}
  end

  test "leaves tests without evidence to other rules" do
    input = input(tests: ["AppTests/CartTests/totalSumsItems()"], changed_files: [changed("App/Cart.swift")])
    assert decide(input) == %{}
  end
end
