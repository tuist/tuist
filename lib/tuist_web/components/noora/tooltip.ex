defmodule TuistWeb.Noora.Tooltip do
  @moduledoc false
  use Phoenix.Component
  import TuistWeb.Noora.Utils
  alias TuistWeb.Noora.Icon

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
    >
      {render_slot(@trigger, %{"data-part" => "trigger"})}
      <%= if @size == "small" do %>
        <div data-part="content" data-size="small">{@title}</div>
      <% end %>
      <%= if @size == "large" do %>
        <div data-part="content" data-size="large">
          <div class="noora-tooltip__icon">
            {render_slot(@icon)}
          </div>
          <div class="noora-tooltip__content">
            <span class="noora-tooltip__title">{@title}</span>
            <span class="noora-tooltip__description">{@description}</span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
