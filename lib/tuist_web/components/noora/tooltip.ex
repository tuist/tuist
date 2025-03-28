defmodule TuistWeb.Noora.Tooltip do
  @moduledoc """
  Renders a tooltip component with a trigger, customizable size, title, description, and optional icon.
  """
  use Phoenix.Component

  import TuistWeb.Noora.Utils

  attr :id, :string, required: true
  attr :disabled, :boolean, default: false

  attr :size, :string, values: ~w(small large), default: "small", doc: "Size of the tooltip"
  attr :title, :string, required: true, doc: "Tooltip title"
  attr :description, :string, doc: "Tooltip description. Only shown when `size` is set to large."

  slot :trigger, required: true, doc: "Tooltip trigger"

  slot :icon,
    doc: "Icon to be rendered inside the tooltip. Only shown when `size` is set to large."

  slot :inner_block, doc: "Content to be rendered inside the tooltip"

  def tooltip(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-tooltip"
      phx-hook="NooraTooltip"
      data-open-delay="250"
      data-close-delay="150"
      data-interactive
      data-positioning-placement="bottom-start"
    >
      {render_slot(@trigger, %{"data-part" => "trigger"})}
      <div data-part="positioner">
        <%= if @size == "small" do %>
          <div data-part="content" data-size="small">{@title}</div>
        <% end %>
        <%= if @size == "large" do %>
          <div data-part="content" data-size="large">
            <div :if={has_slot_content?(@icon, assigns)} data-part="icon">
              {render_slot(@icon)}
            </div>
            <div data-part="body">
              <span data-part="title">{@title}</span>
              <span data-part="description">{@description}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
