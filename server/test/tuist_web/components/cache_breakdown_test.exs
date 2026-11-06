defmodule TuistWeb.Components.CacheBreakdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.CacheBreakdown

  test "the shared breakdown rounds only nonempty outer segments" do
    segments = [%{count: 0}, %{count: 19}, %{count: 1}]
    assert CacheBreakdown.border_radius(segments, 0) == [0, 0, 0, 0]
    assert CacheBreakdown.border_radius(segments, 1) == [6, 0, 0, 6]
    assert CacheBreakdown.border_radius(segments, 2) == [0, 6, 6, 0]
    assert CacheBreakdown.border_radius([%{count: 20}], 0) == [6, 6, 6, 6]
  end

  test "queried actions exclude unconsulted work and retain aggregate attribution" do
    html =
      render_component(&CacheBreakdown.cache_breakdown/1,
        id: "breakdown",
        label: "Queried actions:",
        segments: [
          %{name: "Hit", count: 19, color: "var:hits-chart-legend-remote"},
          %{name: "Missed", count: 1, color: "var:hits-chart-legend-missed"}
        ]
      )

    assert html =~ "Queried actions:"
    assert html =~ ">20<"
    assert html =~ "Hit"
    assert html =~ "Missed"
    refute html =~ "Local"
    refute html =~ "Remote"
  end

  test "zero-count states are omitted from the chart and legend" do
    html =
      render_component(&CacheBreakdown.cache_breakdown/1,
        id: "unchecked-breakdown",
        label: "Cacheable tasks:",
        segments: [
          %{name: "Hit", count: 0, color: "var:hits-chart-legend-remote"},
          %{name: "Missed", count: 20, color: "var:hits-chart-legend-missed"}
        ]
      )

    assert html =~ ">20<"
    assert html =~ "Missed"
    refute html =~ "Hit"
  end

  test "a build without queried actions has no fabricated breakdown" do
    html =
      render_component(&CacheBreakdown.cache_breakdown/1,
        id: "empty-breakdown",
        label: "Queried actions:",
        segments: [%{name: "Hit", count: 0, color: "var:hits-chart-legend-remote"}]
      )

    refute html =~ "empty-breakdown"
  end
end
