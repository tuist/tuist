defmodule TuistWeb.WidgetTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Widget

  test "tooltip icons preserve Noora's interactive trigger attributes" do
    html =
      (&Widget.widget/1)
      |> render_component(
        id: "sample",
        title: "Duration",
        value: "10ms",
        description: "Observed durations",
        legend_color: "secondary"
      )
      |> Floki.parse_fragment!()

    assert [_trigger] = Floki.find(html, "#sample-tooltip [data-part=trigger][tabindex='0']")
    assert Floki.find(html, "#sample-tooltip [data-part=tooltip-icon]") == []
  end
end
