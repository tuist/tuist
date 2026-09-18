defmodule TuistWeb.Coverage.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Coverage.Components

  describe "measured_by_cell/1" do
    test "shows both of two schemes" do
      html = render_component(&Components.measured_by_cell/1, commit: %{schemes: ["App", "Kit"], partial_schemes: []})

      assert html =~ "App"
      assert html =~ "Kit"
      refute html =~ "+"
    end

    test "folds every scheme past the first into a count" do
      html =
        render_component(&Components.measured_by_cell/1,
          commit: %{schemes: ["App", "Kit", "Core"], partial_schemes: ["Core"]}
        )

      assert html =~ "App"
      assert html =~ "+2"
      assert html =~ ~s(title="Kit, Core")
      refute html =~ ">Kit<"
    end
  end
end
