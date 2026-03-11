defmodule Noora.ButtonGroup do
  @moduledoc """
  ButtonGroup component for Noora UI.

  This component allows grouping multiple buttons together with consistent styling and spacing.
  It handles layout, alignment, and proper spacing between buttons in the group.

  ## Example

  ```elixir
  <.button_group size="medium">
    <.button_group_item label="Edit" navigate="/edit" />
    <.button_group_item label="Delete" />
  </.button_group>
  ```
  """

  use Phoenix.Component

  attr(:size, :string, default: "medium", values: ~w(small medium large), doc: "The size of the button group")
  attr(:rest, :global, doc: "Additional HTML attributes")

  slot(:inner_block, required: true, doc: "Button group items to be rendered")

  def button_group(assigns) do
    ~H"""
    <div class="noora-button-group" data-size={@size} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the button group item")
  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:icon_only, :boolean, default: false, doc: "Determines if the button is icon only")
  attr(:rest, :global)

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")
  slot(:inner_block, required: false, doc: "Inner block that renders HEEx content")

  def button_group_item(assigns) do
    ~H"""
    <%= if @href || @navigate || @patch do %>
      <.link
        class="noora-button-group-item"
        href={@href}
        navigate={@navigate}
        patch={@patch}
        data-icon-only={@icon_only}
        {@rest}
      >
        <%= if @icon_left  && !@icon_only do %>
          {render_slot(@icon_left)}
        <% end %>
        <span :if={!@icon_only} data-part="label">{@label}</span>
        <%= if @icon_only do %>
          {render_slot(@inner_block)}
        <% end %>
        <%= if @icon_right && !@icon_only do %>
          {render_slot(@icon_right)}
        <% end %>
      </.link>
    <% else %>
      <button class="noora-button-group-item" data-icon-only={@icon_only} {@rest}>
        <%= if @icon_left  && !@icon_only do %>
          {render_slot(@icon_left)}
        <% end %>
        <span :if={!@icon_only} data-part="label">{@label}</span>
        <%= if @icon_only do %>
          {render_slot(@inner_block)}
        <% end %>
        <%= if @icon_right && !@icon_only do %>
          {render_slot(@icon_right)}
        <% end %>
      </button>
    <% end %>
    """
  end
end
