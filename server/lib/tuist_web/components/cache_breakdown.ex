defmodule TuistWeb.Components.CacheBreakdown do
  @moduledoc false
  use Phoenix.Component
  use Noora

  import TuistWeb.CldrHelpers

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :segments, :list, required: true

  def cache_breakdown(assigns) do
    segments = Enum.filter(assigns.segments, &(&1.count > 0))
    assigns = assign(assigns, segments: segments, total: Enum.sum(Enum.map(segments, & &1.count)))

    ~H"""
    <.card_section :if={@total > 0} data-part="cacheable-tasks-card-section">
      <div data-part="title">
        <span data-part="label">{@label}</span>
        <span data-part="value">{format_number(@total)}</span>
      </div>
      <.chart
        id={@id}
        type="bar"
        extra_options={
          %{
            tooltip: %{trigger: "axis", axisPointer: %{type: "none"}},
            legend: %{
              left: "-0.3%",
              top: "bottom",
              orient: "horizontal",
              textStyle: %{
                color: "var:noora-surface-label-primary",
                fontFamily: "monospace",
                fontWeight: 400,
                fontSize: 10,
                lineHeight: 12
              },
              icon:
                "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
              itemWidth: 8,
              itemHeight: 4
            },
            grid: %{width: "99%", left: "0%", height: "60%", top: "0%"},
            xAxis: %{type: "value", axisLabel: %{show: false}, splitLine: %{show: false}},
            yAxis: %{type: "category", data: [@label], axisLabel: %{show: false}}
          }
        }
        series={
          for {segment, index} <- Enum.with_index(@segments) do
            %{
              name: segment.name,
              type: "bar",
              stack: "total",
              emphasis: %{focus: "series"},
              data: [segment.count],
              color: segment.color,
              itemStyle: %{borderRadius: border_radius(@segments, index)}
            }
          end
        }
        x_axis_min={0}
        x_axis_max={@total}
      />
    </.card_section>
    """
  end

  def border_radius(segments, index) do
    nonempty = for {segment, i} <- Enum.with_index(segments), segment.count > 0, do: i

    if index in nonempty do
      left = if index == List.first(nonempty), do: 6, else: 0
      right = if index == List.last(nonempty), do: 6, else: 0
      [left, right, right, left]
    else
      [0, 0, 0, 0]
    end
  end
end
