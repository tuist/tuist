defmodule Noora.TabMenu do
  @moduledoc """
  Tab menu components.

  ## Example

  ```elixir
  <.tab_menu_horizontal>
    <.tab_menu_horizontal_item
      label="Overview"
      patch={~p"/products/\#{@product}/overview"}
      selected={@tab == :overview}
    />
    <.tab_menu_horizontal_item
      label="Analytics"
      patch={~p"/products/\#{@product}/analytics"}
      selected={@tab == :analytics}
    >
      <:icon_left>
        <.chart_icon />
      </:icon_left>
    </.tab_menu_horizontal_item>
    <.tab_menu_horizontal_item
      label="Settings"
      patch={~p"/products/\#{@product}/settings"}
      selected={@tab == :settings}
    />
  </.tab_menu_horizontal>
  ```
  """
  use Phoenix.Component

  import Noora.Utils

  attr(:label, :string, required: true, doc: "The label of the menu item.")
  attr(:rest, :global)

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")

  def tab_menu_vertical(assigns) do
    ~H"""
    <div class="noora-tab-menu-vertical" {@rest}>
      <%= if has_slot_content?(@icon_left, assigns) do %>
        <div data-part="icon-left">
          {render_slot(@icon_left)}
        </div>
      <% end %>
      <span data-part="label">{@label}</span>
      <%= if has_slot_content?(@icon_right, assigns) do %>
        <div data-part="icon-right">
          {render_slot(@icon_right)}
        </div>
      <% end %>
    </div>
    """
  end

  attr(:rest, :global)
  slot(:inner_block, required: true)

  def tab_menu_horizontal(assigns) do
    ~H"""
    <div class="noora-tab-menu-horizontal" {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the menu item.")
  attr(:selected, :boolean, default: false, doc: "Whether the item is selected.")
  attr(:navigate, :string, default: nil, doc: "Navigate to a different LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")
  attr(:href, :string, default: nil, doc: "External page to link to")
  attr(:replace, :boolean, default: true, doc: "Whether to replace the current item in the history")
  attr(:rest, :global)

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")

  def tab_menu_horizontal_item(assigns) do
    ~H"""
    <%= if @patch || @navigate || @href do %>
      <.link
        class="noora-tab-menu-horizontal-item"
        patch={@patch}
        replace={@replace}
        navigate={@navigate}
        href={@href}
        data-selected={@selected}
        {@rest}
      >
        <%= if has_slot_content?(@icon_left, assigns) do %>
          <div data-part="icon-left">
            {render_slot(@icon_left)}
          </div>
        <% end %>
        <span data-part="label">{@label}</span>
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
        <span data-part="label">{@label}</span>
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
