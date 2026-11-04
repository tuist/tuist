defmodule Tuist.TestImpactAnalysis.Rules.TestFileChangedTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.TestFileChanged
  alias Tuist.TestImpactAnalysis.State

  defp decide(input, state \\ State.new()) do
    {state, :continue} = TestFileChanged.decide(input, state)
    state.decisions
  end

  test "selects every test of the suite a changed test file belongs to" do
    input =
      input(
        tests: [
          "CoreTests/DiscountTests/testTenPercent",
          "CoreTests/DiscountTests/testZeroPercent",
          "CoreTests/MoneyTests/testAdds"
        ],
        test_paths: ["CoreTests/DiscountTests.swift", "CoreTests/MoneyTests.swift"],
        versions: %{
          # Only one of the suite's tests' evidence includes its file.
          "CoreTests/DiscountTests/testTenPercent" => [
            version(%{"CoreTests/DiscountTests.swift" => "t1", "Core/Discount.swift" => "d1"})
          ],
          "CoreTests/MoneyTests/testAdds" => [version(%{"CoreTests/MoneyTests.swift" => "m1"})]
        },
        changed_files: [changed("CoreTests/DiscountTests.swift")]
      )

    assert decide(input) == %{
             "CoreTests/DiscountTests/testTenPercent" => %{
               decision: :selected,
               reason: :test_file_changed,
               matched_path: "CoreTests/DiscountTests.swift"
             },
             "CoreTests/DiscountTests/testZeroPercent" => %{
               decision: :selected,
               reason: :test_file_changed,
               matched_path: "CoreTests/DiscountTests.swift"
             }
           }
  end

  test "selects the suite of a deleted test file, whose tests the checkout no longer has" do
    input =
      input(
        tests: [
          "CoreTests/MoneyTests/testFormats",
          "CoreTests/MoneyTests/testAdds",
          "CoreTests/DiscountTests/testTenPercent"
        ],
        test_paths: ["CoreTests/MoneyTests.swift", "CoreTests/DiscountTests.swift"],
        versions: %{
          "CoreTests/MoneyTests/testFormats" => [version(%{"CoreTests/MoneyTests.swift" => "m1"})],
          "CoreTests/MoneyTests/testAdds" => [version(%{"CoreTests/MoneyTests.swift" => "m1"})],
          "CoreTests/DiscountTests/testTenPercent" => [version(%{"CoreTests/DiscountTests.swift" => "d1"})]
        },
        changed_files: [changed("CoreTests/MoneyTests.swift", status: "D", blob: nil)]
      )

    assert decide(input) == %{
             "CoreTests/MoneyTests/testFormats" => %{
               decision: :selected,
               reason: :test_file_changed,
               matched_path: "CoreTests/MoneyTests.swift"
             },
             "CoreTests/MoneyTests/testAdds" => %{
               decision: :selected,
               reason: :test_file_changed,
               matched_path: "CoreTests/MoneyTests.swift"
             }
           }
  end

  test "selects through the suite's setup evidence" do
    input =
      input(
        tests: ["CatalogTests/LoadingTests/testCount"],
        test_paths: ["CatalogTests/Support.swift"],
        versions: %{
          "CatalogTests/LoadingTests/testCount" => [version(%{"CatalogTests/Support.swift" => "s1"})]
        },
        changed_files: [changed("CatalogTests/Support.swift")]
      )

    assert %{"CatalogTests/LoadingTests/testCount" => %{reason: :test_file_changed}} = decide(input)
  end

  test "ignores changed files the baseline didn't record as test code" do
    input =
      input(
        tests: ["CoreTests/DiscountTests/testTenPercent"],
        versions: %{"CoreTests/DiscountTests/testTenPercent" => [version(%{"Core/Discount.swift" => "d1"})]},
        changed_files: [changed("Core/Discount.swift")]
      )

    assert decide(input) == %{}
  end

  test "records the first matching file in path order" do
    input =
      input(
        tests: ["AppTests/CartTests/testTotal"],
        test_paths: ["AppTests/B.swift", "AppTests/A.swift"],
        versions: %{"AppTests/CartTests/testTotal" => [version(%{"AppTests/A.swift" => "a", "AppTests/B.swift" => "b"})]},
        changed_files: [changed("AppTests/B.swift"), changed("AppTests/A.swift")]
      )

    assert %{"AppTests/CartTests/testTotal" => %{matched_path: "AppTests/A.swift"}} = decide(input)
  end

  test "selects only the test itself when it has no suite" do
    input =
      input(
        tests: ["AppTests//testOne", "AppTests//testTwo"],
        test_paths: ["AppTests/One.swift"],
        versions: %{"AppTests//testOne" => [version(%{"AppTests/One.swift" => "o"})]},
        changed_files: [changed("AppTests/One.swift")]
      )

    assert Map.keys(decide(input)) == ["AppTests//testOne"]
  end

  test "leaves decided tests alone" do
    input =
      input(
        tests: ["CoreTests/DiscountTests/testTenPercent"],
        test_paths: ["CoreTests/DiscountTests.swift"],
        versions: %{"CoreTests/DiscountTests/testTenPercent" => [version(%{"CoreTests/DiscountTests.swift" => "t"})]},
        changed_files: [changed("CoreTests/DiscountTests.swift")]
      )

    state = State.skip(State.new(), "CoreTests/DiscountTests/testTenPercent", :earlier)
    assert %{"CoreTests/DiscountTests/testTenPercent" => %{reason: :earlier}} = decide(input, state)
  end
end
