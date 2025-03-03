defmodule TuistWeb.Noora.Chart do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :option, :map, required: true

  def chart(assigns) do
    ~H"""
    <div id={@id} class="noora-chart" phx-hook="NooraChart">
      {# The actual chart is managed by ECharts, so we are ignoring any updates by LiveView. The chart should be updated by changing the `@option` assign instead. #}
      <div id={"#{@id}-chart"} data-part="chart" phx-update="ignore"></div>
      <div data-part="data" hidden>{Jason.encode!(@option)}</div>
    </div>
    """
  end
end
