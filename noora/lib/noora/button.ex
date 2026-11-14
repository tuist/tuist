defmodule Noora.Button do
  @moduledoc """
  A component for rendering both standard buttons and link-style buttons, offering flexible styling options for variants, sizes, and icon placement.
  """

  use Phoenix.Component

  @button_variants ~w(primary secondary destructive)
  @button_sizes ~w(small medium large)
  @variant_doc "Controls the visual emphasis and semantic intent."
  @size_doc "Controls the button dimensions and text size."

  def button_variants, do: @button_variants
  def button_sizes, do: @button_sizes

  attr(:label, :string, default: "", doc: "Provides fallback text when the default slot is empty.")

  attr(:variant, :string, values: @button_variants, default: "primary", doc: @variant_doc)

  attr(:size, :string, values: @button_sizes, default: "large", doc: @size_doc)

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:icon_only, :boolean,
    default: false,
    doc: "Uses the default slot as the entire button content. An accessible label is required."
  )

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")
  slot(:inner_block, required: false, doc: "Inner block that renders HEEx content")

  attr(:rest, :global, include: ~w(phx-click disabled form target rel type))

  def button(assigns) do
    ~H"""
    <%= if (@href || @navigate || @patch) && !@rest[:disabled] do %>
      <.link
        class="noora-button"
        href={@href}
        navigate={@navigate}
        patch={@patch}
        data-variant={@variant}
        data-size={@size}
        data-icon-only={@icon_only}
        {@rest}
      >
        <%= if @icon_left  && !@icon_only do %>
          {render_slot(@icon_left)}
        <% end %>
        <span :if={!@icon_only}>{@label}</span>
        <%= if @icon_only do %>
          {render_slot(@inner_block)}
        <% end %>
        <%= if @icon_right && !@icon_only do %>
          {render_slot(@icon_right)}
        <% end %>
      </.link>
    <% else %>
      <button
        class="noora-button"
        data-variant={@variant}
        data-size={@size}
        data-icon-only={@icon_only}
        {@rest}
      >
        <%= if @icon_left  && !@icon_only do %>
          {render_slot(@icon_left)}
        <% end %>
        <span :if={!@icon_only}>{@label}</span>
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

  attr(:variant, :string, values: @button_variants, default: "primary", doc: @variant_doc)

  attr(:size, :string, values: @button_sizes, default: "large", doc: @size_doc)

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:label, :string,
    default: nil,
    doc: "The label of the button. When set, the inner block is replaced by the label and the icon slots."
  )

  slot(:icon_left, doc: "Icon displayed on the left of the label")
  slot(:icon_right, doc: "Icon displayed on the right of the label")

  slot(:inner_block,
    required: false,
    doc: "Inner block that renders HEEx content when no label is set"
  )

  attr(:rest, :global, include: ~w(phx-click disabled form target rel type))

  def neutral_button(assigns) do
    ~H"""
    <%= if @href || @navigate || @patch do %>
      <.link
        class="noora-neutral-button"
        href={@href}
        navigate={@navigate}
        patch={@patch}
        data-variant={@variant}
        data-size={@size}
        data-with-label={!is_nil(@label)}
        {@rest}
      >
        <%= if @label do %>
          {render_slot(@icon_left)}
          <span data-part="label">{@label}</span>
          {render_slot(@icon_right)}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </.link>
    <% else %>
      <button
        class="noora-neutral-button"
        data-variant={@variant}
        data-size={@size}
        data-with-label={!is_nil(@label)}
        {@rest}
      >
        <%= if @label do %>
          {render_slot(@icon_left)}
          <span data-part="label">{@label}</span>
          {render_slot(@icon_right)}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </button>
    <% end %>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the button")

  attr(:variant, :string, values: @button_variants, default: "primary", doc: @variant_doc)

  attr(:size, :string, values: @button_sizes, default: "large", doc: @size_doc)

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:underline, :boolean, default: false, doc: "Determines if the button is underlined")

  attr(:rest, :global, include: ~w(target rel))

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")

  def link_button(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      patch={@patch}
      class="noora-link-button"
      data-variant={@variant}
      data-size={@size}
      data-underline={@underline}
      {@rest}
    >
      <%= if @icon_left do %>
        {render_slot(@icon_left)}
      <% end %>
      <span>{@label}</span>
      <%= if @icon_right do %>
        {render_slot(@icon_right)}
      <% end %>
    </.link>
    """
  end
end
