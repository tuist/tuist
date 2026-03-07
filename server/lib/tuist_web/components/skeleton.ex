defmodule TuistWeb.Components.Skeleton do
  @moduledoc """
  Skeleton loading placeholder components.

  These components provide visual placeholders that are displayed while data
  is being loaded asynchronously, giving users a preview of the layout.
  """
  use Phoenix.Component

  attr(:title_width, :string, default: nil, doc: "Optional CSS width for the title placeholder.")
  attr(:value_width, :string, default: nil, doc: "Optional CSS width for the value placeholder.")

  def skeleton_legend(assigns) do
    ~H"""
    <div class="tuist-legend">
      <div data-part="header">
        <div data-part="indicator"></div>
        <span
          data-part="title"
          class="tuist-loading-skeleton"
          style={@title_width && "min-width: #{@title_width}"}
        >
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
        </span>
      </div>
      <span
        data-part="value"
        class="tuist-loading-skeleton"
        style={@value_width && "min-width: #{@value_width}"}
      >
        &nbsp;&nbsp;&nbsp;
      </span>
    </div>
    """
  end

  attr(:height, :string, default: nil, doc: "Optional fixed height for the chart placeholder.")

  def skeleton_chart(assigns) do
    ~H"""
    <div
      class="noora-chart tuist-loading-skeleton"
      style={
        [
          "width: 100%",
          @height && "height: #{@height}"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("; ")
      }
    >
      &nbsp;
    </div>
    """
  end

  attr(:width, :string, required: true, doc: "CSS width for the box.")
  attr(:height, :string, required: true, doc: "CSS height for the box.")
  attr(:border_radius, :string, default: nil, doc: "Optional CSS border-radius override.")

  def skeleton_box(assigns) do
    ~H"""
    <div
      class="tuist-loading-skeleton"
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
