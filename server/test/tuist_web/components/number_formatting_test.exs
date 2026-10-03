defmodule TuistWeb.Components.NumberFormattingTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.AppComponents
  alias TuistWeb.Components.ModuleInvalidationsTable
  alias TuistWeb.Widget

  test "widgets and legends humanize large metrics and preserve formatted units" do
    for {value, expected} <- [
          {2_901_412, "2.9M"},
          {18_672.5, "18.7K"},
          {836, "836"},
          {"98.5%", "98.5%"},
          {"125ms", "125ms"},
          {1.25, "1.25"}
        ] do
      widget = render_component(&Widget.widget/1, %{id: "metric", title: "Hits", value: value})
      legend = render_component(&AppComponents.legend/1, %{title: "Hits", value: value})

      assert Floki.text(Floki.find(Floki.parse_fragment!(widget), "[data-part=value]")) == expected
      assert Floki.text(Floki.find(Floki.parse_fragment!(legend), "[data-part=value]")) == expected
    end
  end

  test "module tables humanize misses and dependents without changing hit rates or row identity" do
    rows = [%{name: "ExampleModule", invalidations: 121_755, blast_radius: 24_420, hit_rate: 71.5}]
    html = render_component(&ModuleInvalidationsTable.module_invalidations_table/1, %{id: "modules", rows: rows})

    assert html =~ "121.8K"
    assert html =~ "24.4K"
    assert html =~ "71.5%"
    assert html =~ "ExampleModule"
  end
end
