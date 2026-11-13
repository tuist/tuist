defmodule Tuist.TestImpactAnalysis.Rules.TrackedFilesTest do
  use ExUnit.Case, async: true

  import TuistTestSupport.Fixtures.TestImpactAnalysisFixtures

  alias Tuist.TestImpactAnalysis.Rules.TrackedFiles
  alias Tuist.TestImpactAnalysis.State

  @globs ["**/Package.resolved", "**/*.xcconfig", ".xcode-version"]

  test "aborts with the first tracked path in path order" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        tracked_file_globs: @globs,
        changed_files: [changed("Tuist/Package.resolved"), changed("Configs/Base.xcconfig"), changed("Core/Money.swift")]
      )

    assert TrackedFiles.decide(input, State.new()) ==
             {State.new(), {:abort, :tracked_file_changed, "Configs/Base.xcconfig"}}
  end

  test "matches a root-only glob only at the root" do
    input = input(tracked_file_globs: @globs, changed_files: [changed("docs/.xcode-version")])
    assert {_state, :continue} = TrackedFiles.decide(input, State.new())

    input = input(tracked_file_globs: @globs, changed_files: [changed(".xcode-version")])
    assert {_state, {:abort, :tracked_file_changed, ".xcode-version"}} = TrackedFiles.decide(input, State.new())
  end

  test "continues and decides nothing when no tracked file changed" do
    input =
      input(
        tests: ["CoreTests/MoneyTests/testAdds"],
        tracked_file_globs: @globs,
        changed_files: [changed("Core/Money.swift")]
      )

    assert TrackedFiles.decide(input, State.new()) == {State.new(), :continue}
  end

  test "continues without globs" do
    input = input(changed_files: [changed("Configs/Base.xcconfig")])
    assert TrackedFiles.decide(input, State.new()) == {State.new(), :continue}
  end
end
