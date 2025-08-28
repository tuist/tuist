defmodule TuistWeb.Components.TrendBadge do
  @moduledoc """
    Component for displaying a trend badge.
  """
  use Phoenix.Component
  use Noora

  attr :trend_value, :integer, required: true
  attr :trend_inverse, :boolean, default: false

  def trend_badge(assigns) do
    rounded = Float.round(assigns.trend_value, 1)

    formatted_value =
      if abs(rounded) < 0.1 and rounded != 0.0 do
        "0.0"
      else
        :erlang.float_to_binary(rounded, decimals: if(abs(rounded) >= 1000, do: 0, else: 1))
      end

    ~H"""
    <.badge
      size="large"
      label={
        if @trend_value > 0,
          do: "+#{formatted_value}%",
          else: "#{formatted_value}%"
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
