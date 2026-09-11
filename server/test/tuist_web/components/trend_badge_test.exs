defmodule TuistWeb.Components.TrendBadgeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.TrendBadge

  test "zero trends default to No change with neutral styling and no arrow" do
    for type <- [:regular, :inverse, :neutral], value <- [0, 0.0] do
      html = render_component(&TrendBadge.trend_badge/1, %{trend_value: value, trend_type: type})
      assert html =~ "No change"
      assert html =~ ~s(data-color="neutral")
      refute html =~ "%"
      assert Floki.find(Floki.parse_fragment!(html), "svg") == []
    end
  end

  test "nonzero trends preserve percentages and semantic colors" do
    html = render_component(&TrendBadge.trend_badge/1, %{trend_value: 5.0, trend_type: :inverse})
    assert html =~ "+5.0%"
    assert html =~ ~s(data-color="destructive")
  end

  test "an explicit label still supports percentage points and absolute values" do
    html = render_component(&TrendBadge.trend_badge/1, %{trend_value: 5.0, label: "+5 pp"})
    assert html =~ "+5 pp"
    refute html =~ "+5.0%"
  end
end
