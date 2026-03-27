defmodule Noora.Sidebar do
  @moduledoc """
  A flexible sidebar.

  ## Example

  ```elixir
  <.sidebar>
    <.sidebar_item
      label="Dashboard"
      icon="home"
      patch={~p"/dashboard"}
      selected={@live_action == :dashboard}
    />
    <.sidebar_group
      id="products-group"
      label="Products"
      icon="package"
      collapsible={true}
      default_open={true}
    >
      <.sidebar_item
        label="All Products"
        icon="list"
        patch={~p"/products"}
      />
      <.sidebar_item
        label="Add Product"
        icon="plus"
        patch={~p"/products/new"}
      />
    </.sidebar_group>
  </.sidebar>
  ```
  """

  use Phoenix.Component

  import Noora.Icon
  import Noora.TabMenu

  slot(:inner_block, required: true)

  def sidebar(assigns) do
    ~H"""
    <div class="noora-sidebar" data-part="sidebar">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:icon, :string, required: true, doc: "The icon of the group.")
  attr(:label, :string, required: true, doc: "The label of the group.")
  attr(:collapsible, :boolean, default: true, doc: "Whether the group is collapsible.")
  attr(:default_open, :boolean, default: false, doc: "Whether the group is open by default.")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")
  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:selected, :boolean, default: false, doc: "Whether the item is selected.")
  attr(:disabled, :boolean, default: false, doc: "Whether the item is disabled.")

  attr(:rest, :global)
  slot(:inner_block)

  def sidebar_group(assigns) do
    ~H"""
    <%= if @collapsible do %>
      <div
        id={@id}
        data-part="collapsible-group"
        phx-hook="NooraCollapsible"
        data-open={@default_open}
        data-disabled={@disabled}
        {@rest}
      >
        <div data-part="root">
          <%= if @navigate || @patch || @href do %>
            <.link navigate={@navigate} patch={@patch} href={@href} data-part="trigger">
              <.tab_menu_vertical label={@label} data-selected={@selected}>
                <:icon_left><.icon name={@icon} /></:icon_left>
                <:icon_right>
                  <div data-part="indicator">
                    <div data-part="indicator-down">
                      <.chevron_down />
                    </div>
                    <div data-part="indicator-up">
                      <.chevron_up />
                    </div>
                  </div>
                </:icon_right>
              </.tab_menu_vertical>
            </.link>
          <% else %>
            <.tab_menu_vertical label={@label} data-part="trigger" data-selected={@selected}>
              <:icon_left><.icon name={@icon} /></:icon_left>
              <:icon_right>
                <div data-part="indicator">
                  <div data-part="indicator-down">
                    <.chevron_down />
                  </div>
                  <div data-part="indicator-up">
                    <.chevron_up />
                  </div>
                </div>
              </:icon_right>
            </.tab_menu_vertical>
          <% end %>
          <div data-part="content">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    <% else %>
      <div id={@id} data-part="group" {@rest}>
        <span data-part="group-label">{@label}</span>
        {render_slot(@inner_block)}
      </div>
    <% end %>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the item.")
  attr(:icon, :string, required: true, doc: "The icon of the item.")
  attr(:selected, :boolean, default: false, doc: "Whether the item is selected.")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")
  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:rest, :global)

  def sidebar_item(assigns) do
    ~H"""
    <.link navigate={@navigate} patch={@patch} href={@href} data-part="item">
      <.tab_menu_vertical label={@label} data-selected={@selected}>
        <:icon_left>
          <.icon name={@icon} />
        </:icon_left>
      </.tab_menu_vertical>
    </.link>
    """
  end
end
