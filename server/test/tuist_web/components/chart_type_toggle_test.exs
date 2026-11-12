defmodule TuistWeb.Components.ChartTypeToggleTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.ChartTypeToggle

  test "existing consumers default to line and scatter" do
    html = render_toggle([])
    assert Floki.find(html, "[phx-value-type='line'][data-selected]") != []
    assert Floki.find(html, "[phx-value-type='scatter']") != []
    assert Floki.find(html, "[phx-value-type='bar']") == []
  end

  test "bucket charts can supply bar and line without scatter" do
    html = render_toggle(chart_types: ~w(bar line), chart_type: "bar")
    assert Floki.find(html, "[phx-value-type='bar'][data-selected]") != []
    assert Floki.find(html, "[phx-value-type='line']") != []
    assert Floki.find(html, "[phx-value-type='scatter']") == []
  end

  defp render_toggle(options) do
    defaults = [id: "format", chart_type: "line", chart_type_event: "select_type", uri: URI.parse("/analytics")]

    (&ChartTypeToggle.chart_type_toggle/1)
    |> render_component(Keyword.merge(defaults, options))
    |> Floki.parse_document!()
  end
end
