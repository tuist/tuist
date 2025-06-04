defmodule TuistWeb.Components.TrendBadge do
  @moduledoc """
    Component for displaying a trend badge.
  """
  use Phoenix.Component
  use Noora

  attr :trend_value, :integer, required: true
  attr :trend_inverse, :boolean, default: false

  def trend_badge(assigns) do
    ~H"""
    <.badge
      size="large"
      label={
        if @trend_value > 0,
          do: "+#{@trend_value |> Float.round(1)}%",
          else: "#{@trend_value |> Float.round(1)}%"
      }
      color={
        cond do
          @trend_value < 0 and not @trend_inverse -> "destructive"
          @trend_value < 0 and @trend_inverse -> "success"
          @trend_value > 0 and not @trend_inverse -> "success"
          @trend_value > 0 and @trend_inverse -> "destructive"
          true -> "neutral"
        end
      }
      style="light-fill"
    >
      <:icon :if={@trend_value != 0}>
        <.trending_up :if={@trend_value > 0} />
        <.trending_down :if={@trend_value < 0} />
      </:icon>
    </.badge>
    """
  end
end
