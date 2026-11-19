defmodule Noora.MiddleTruncateTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias Noora.MiddleTruncate

  doctest MiddleTruncate

  describe "split/1" do
    test "keeps the last segment after a separator as the tail" do
      assert MiddleTruncate.split("northwind_industries-ios-app-v12") == {"northwind_industries-ios-app", "-v12"}

      assert MiddleTruncate.split("app/routes/projects/settings/members.ex") ==
               {"app/routes/projects/settings", "/members.ex"}
    end

    test "falls back to the last 8 characters when no separator is near the end" do
      assert MiddleTruncate.split("TuistAcceptanceTestsSimulatorRelease") ==
               {"TuistAcceptanceTestsSimulato", "rRelease"}

      {head, tail} = MiddleTruncate.split("9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f")
      assert tail == "9c8d7e6f"
      assert head <> tail == "9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f"
    end

    test "leaves short strings whole" do
      assert MiddleTruncate.split("android-app") == {"android-app", ""}
    end

    test "never splits a character, including emoji" do
      value = "🦊-fox-workspace-for-the-northwind-team-👩🏽‍💻"
      {head, tail} = MiddleTruncate.split(value)

      assert head <> tail == value
      assert tail == "-team-👩🏽‍💻"
    end
  end

  test "renders the head and tail with the full value as the title" do
    assigns = %{}

    html = rendered_to_string(~H|<MiddleTruncate.middle_truncate value="TuistAcceptanceTests-iOS-Simulator-Release" />|)

    assert html =~ ~s(title="TuistAcceptanceTests-iOS-Simulator-Release")

    short = rendered_to_string(~H|<MiddleTruncate.middle_truncate value="ios-app" />|)
    refute short =~ "title="

    assert html =~
             ~s(<span data-part="head">TuistAcceptanceTests-iOS-Simulator</span><span data-part="tail">-Release</span>)
  end
end
