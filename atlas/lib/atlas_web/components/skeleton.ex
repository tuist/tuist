defmodule AtlasWeb.Components.Skeleton do
  @moduledoc """
  Shimmering placeholders displayed while a section is streaming in through
  `assign_async/3`. Mirrors the Tuist server's skeleton components so the
  Atlas overview reads the same as the customer-facing dashboards.
  """
  use Phoenix.Component

  attr :height, :string, default: nil, doc: "Optional fixed height for the chart placeholder."

  def skeleton_chart(assigns) do
    ~H"""
    <div
      class="atlas-loading-skeleton atlas-loading-skeleton--chart"
      style={@height && "height: #{@height}"}
    >
      &nbsp;
    </div>
    """
  end

  attr :width, :string, required: true
  attr :height, :string, required: true
  attr :border_radius, :string, default: nil

  def skeleton_box(assigns) do
    ~H"""
    <div
      class="atlas-loading-skeleton"
      style={
        [
          "width: #{@width}",
          "height: #{@height}",
          @border_radius && "border-radius: #{@border_radius}"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("; ")
      }
    >
      &nbsp;
    </div>
    """
  end
end
