defmodule TuistWeb.Components.AsyncCard do
  @moduledoc """
  Coordinates the required results of an analytics card without changing its layout.

  The inner slot receives a readiness flag in both loading and ready states. Use
  that flag for the existing loading/data branches, and guard every required
  result read with it. Optional results keep their own guards. Header actions
  remain available while loading. Successful results stay mounted on refresh.
  """
  use Phoenix.Component

  import Noora.Card

  alias TuistWeb.Components.ErrorCardSection

  attr(:icon, :string, required: true)
  attr(:title, :string, required: true)
  attr(:results, :list, required: true)
  attr(:chart_frame, :string, default: "standard")
  attr(:rest, :global)
  slot(:actions)
  slot(:inner_block, required: true)

  def async_card(assigns) do
    state = async_state(assigns.results)

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(
        :rest,
        Map.merge(assigns.rest, %{
          "data-async-card" => true,
          "data-state" => state,
          "aria-busy" => if(state in [:loading, :refreshing], do: "true", else: "false")
        })
      )

    ~H"""
    <.card icon={@icon} title={@title} {@rest}>
      <:actions>{render_slot(@actions)}</:actions>
      <ErrorCardSection.error_card_section :if={@state == :failed} data-chart-frame={@chart_frame} />
      {if @state != :failed, do: render_slot(@inner_block, @state in [:ready, :refreshing])}
    </.card>
    """
  end

  attr(:results, :list, required: true)
  attr(:chart_frame, :string, default: "standard")
  slot(:inner_block, required: true)

  def async_section(assigns) do
    assigns = assign(assigns, :state, async_state(assigns.results))

    ~H"""
    <ErrorCardSection.error_card_section :if={@state == :failed} data-chart-frame={@chart_frame} />
    {if @state != :failed, do: render_slot(@inner_block, @state in [:ready, :refreshing])}
    """
  end

  def async_state(results) do
    cond do
      Enum.any?(results, &(&1 && &1.failed)) -> :failed
      not Enum.all?(results, &(&1 && &1.ok?)) -> :loading
      Enum.any?(results, &(&1 && &1.loading)) -> :refreshing
      true -> :ready
    end
  end
end
