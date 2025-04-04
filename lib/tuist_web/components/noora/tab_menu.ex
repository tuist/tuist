defmodule TuistWeb.Noora.TabMenu do
  @moduledoc """
  Tab menu components.
  """
  use Phoenix.Component

  import TuistWeb.Noora.Utils

  attr :label, :string, required: true, doc: "The label of the menu item."
  attr :rest, :global

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"

  def tab_menu_vertical(assigns) do
    ~H"""
    <div class="noora-tab-menu-vertical" {@rest}>
      <%= if has_slot_content?(@icon_left, assigns) do %>
        <div data-part="icon-left">
          {render_slot(@icon_left)}
        </div>
      <% end %>
      <div data-part="label">{@label}</div>
      <%= if has_slot_content?(@icon_right, assigns) do %>
        <div data-part="icon-right">
          {render_slot(@icon_right)}
        </div>
      <% end %>
    </div>
    """
  end

  slot :inner_block, required: true

  def tab_menu_horizontal(assigns) do
    ~H"""
    <div class="noora-tab-menu-horizontal">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true, doc: "The label of the menu item."
  attr :selected, :boolean, default: false, doc: "Whether the item is selected."
  attr :patch, :string, default: nil, doc: "Patches the current LiveView"
  attr :rest, :global

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"

  def tab_menu_horizontal_item(assigns) do
    ~H"""
    <%= if @patch do %>
      <.link class="noora-tab-menu-horizontal-item" patch={@patch} data-selected={@selected} {@rest}>
        <%= if has_slot_content?(@icon_left, assigns) do %>
          <div data-part="icon-left">
            {render_slot(@icon_left)}
          </div>
        <% end %>
        <div data-part="label">{@label}</div>
        <%= if has_slot_content?(@icon_right, assigns) do %>
          <div data-part="icon-right">
            {render_slot(@icon_right)}
          </div>
        <% end %>
      </.link>
    <% else %>
      <div class="noora-tab-menu-horizontal-item" data-selected={@selected} {@rest}>
        <%= if has_slot_content?(@icon_left, assigns) do %>
          <div data-part="icon-left">
            {render_slot(@icon_left)}
          </div>
        <% end %>
        <div data-part="label">{@label}</div>
        <%= if has_slot_content?(@icon_right, assigns) do %>
          <div data-part="icon-right">
            {render_slot(@icon_right)}
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
