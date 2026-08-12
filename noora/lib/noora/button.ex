defmodule Noora.Button do
  @moduledoc """
  A component for rendering both standard buttons and link-style buttons, offering flexible styling options for variants, sizes, and icon placement.
  """

  use Phoenix.Component

  @button_contract_path Path.expand("../../components/button.json", __DIR__)
  @external_resource @button_contract_path
  @button_contract @button_contract_path |> File.read!() |> Jason.decode!()
  @button_attributes Map.new(@button_contract["attributes"], &{&1["name"], &1})
  @variant_contract Map.fetch!(@button_attributes, "variant")
  @size_contract Map.fetch!(@button_attributes, "size")
  @label_contract Map.fetch!(@button_attributes, "label")
  @icon_only_contract Map.fetch!(@button_attributes, "icon-only")
  @button_variants @variant_contract["values"]
  @button_sizes @size_contract["values"]
  @default_variant @variant_contract["default"]
  @default_size @size_contract["default"]
  @button_class @button_contract["className"]

  def button_variants, do: @button_variants
  def button_sizes, do: @button_sizes

  attr(:label, :string, default: @label_contract["default"], doc: @label_contract["description"])

  attr(:variant, :string,
    values: @button_variants,
    default: @default_variant,
    doc: @variant_contract["description"]
  )

  attr(:size, :string,
    values: @button_sizes,
    default: @default_size,
    doc: @size_contract["description"]
  )

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:icon_only, :boolean,
    default: @icon_only_contract["default"],
    doc: @icon_only_contract["description"]
  )

  slot(:icon_left, doc: "Icon displayed on the left of an item")
  slot(:icon_right, doc: "Icon displayed on the right of an item")
  slot(:inner_block, required: false, doc: "Inner block that renders HEEx content")

  attr(:rest, :global, include: ~w(phx-click disabled form))

  def button(assigns) do
    ~H"""
    <%= if (@href || @navigate || @patch) && !@rest[:disabled] do %>
      <.link
        class={button_class()}
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
        class={button_class()}
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

  attr(:label, :string, default: nil, doc: "The label of the button")

  attr(:variant, :string,
    values: @button_variants,
    default: @default_variant,
    doc: @variant_contract["description"]
  )

  attr(:size, :string,
    values: @button_sizes,
    default: @default_size,
    doc: @size_contract["description"]
  )

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  slot(:inner_block, required: false, doc: "Inner block that renders HEEx content")

  attr(:rest, :global, include: ~w(phx-click disabled))

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
        {@rest}
      >
        <span :if={@label}>{@label}</span>
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button class="noora-neutral-button" data-variant={@variant} data-size={@size} {@rest}>
        <span :if={@label}>{@label}</span>
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the button")

  attr(:variant, :string,
    values: @button_variants,
    default: @default_variant,
    doc: @variant_contract["description"]
  )

  attr(:size, :string,
    values: @button_sizes,
    default: @default_size,
    doc: @size_contract["description"]
  )

  attr(:href, :any, default: nil, doc: "Uses traditional browser navigation to the new location")
  attr(:navigate, :string, default: nil, doc: "Navigates to a LiveView")
  attr(:patch, :string, default: nil, doc: "Patches the current LiveView")

  attr(:underline, :boolean, default: false, doc: "Determines if the button is underlined")

  attr(:rest, :global)

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

  defp button_class, do: @button_class
end
