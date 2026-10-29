defmodule Noora.ChartTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Noora.Chart

  test "uses item tooltips for custom charts" do
    html =
      render_component(&Chart.chart/1, %{
        id: "timeline",
        type: "custom",
        series: [%{type: "custom", renderItem: "fn:rangeBar", data: []}],
        extra_options: %{tooltip: %{formatter: "fn:rangeBarTooltip"}}
      })

    assert html =~ ~s(&quot;trigger&quot;:&quot;item&quot;)
    assert html =~ ~s(&quot;formatter&quot;:&quot;fn:rangeBarTooltip&quot;)
    assert html =~ ~s(&quot;renderItem&quot;:&quot;fn:rangeBar&quot;)
  end
end
