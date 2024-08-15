defmodule TuistWeb.MarketingLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  import TuistWeb.MarketingIcons

  embed_templates "marketing_layout_components/*"

  slot :inner_block, required: false

  attr :class, :string, default: ""
  attr :flavor, :string, values: ["primary", "secondary"], default: "primary"

  def marketing_link(assigns) do
    assigns =
      assign(
        assigns,
        :font_class,
        case Map.get(assigns, :flavor) do
          "primary" -> "font-l-strong"
          "secondary" -> "font-xs"
        end
      )

    ~H"""
    <.link class={"marketing__component__link #{@font_class} #{@class}"} data-flavor={@flavor}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  attr :size, :string, default: "medium", values: ["medium"]
  attr :href, :string, required: false
  attr :rest, :global
  attr :target, :string, required: false

  def primary_icon_button(assigns) do
    ~H"""
    <%= if assigns[:href] do %>
      <.link
        class="marketing__component__primary__icon__button"
        href={@href}
        target={assigns[:target]}
        {@rest}
      >
        <.icon_arrow_narrow_right />
      </.link>
    <% else %>
      <button {@rest} class="marketing__component__primary__icon__button">
        <.icon_arrow_narrow_right />
      </button>
    <% end %>
    """
  end

  attr :size, :string, required: true, values: ["big", "medium", "small"]
  attr :href, :string, required: false
  attr :target, :string, required: false
  attr :rest, :global
  slot :inner_block, required: false

  def primary_button(assigns) do
    assigns = assign(assigns, :size, Map.get(assigns, :size, "medium"))

    font_class =
      case assigns[:size] do
        "big" -> "font-l-strong"
        "medium" -> "font-m-strong"
        "small" -> "font-xs-strong"
      end

    assigns = assigns |> assign(:font_class, font_class)

    ~H"""
    <%= if assigns[:href] do %>
      <a
        href={assigns[:href]}
        target={assigns[:target]}
        {@rest}
        class={"marketing__component__primary__button #{@font_class}"}
        data-size={@size}
      >
        <%= render_slot(@inner_block) %>
      </a>
    <% else %>
      <button {@rest} class={"marketing__component__primary__button #{@font_class}"} data-size={@size}>
        <%= render_slot(@inner_block) %>
      </button>
    <% end %>
    """
  end

  attr :size, :string, required: true, values: ["big", "medium", "small"]
  attr :variant, :string, required: true, values: ["light", "dark"]
  attr :href, :string, required: false
  attr :target, :string, required: false
  attr :rest, :global
  slot :inner_block, required: false

  def secondary_button(assigns) do
    font_class =
      case assigns[:size] do
        "big" -> "font-l-strong"
        "medium" -> "font-m-strong"
        "small" -> "font-xs-strong"
      end

    assigns = assigns |> assign(:font_class, font_class)

    ~H"""
    <%= if assigns[:href] do %>
      <a
        href={assigns[:href]}
        target={assigns[:target]}
        {@rest}
        class={"marketing__component__secondary__button #{@font_class}"}
        data-size={@size}
        data-variant={@variant}
      >
        <%= render_slot(@inner_block) %>
      </a>
    <% else %>
      <button
        {@rest}
        class={"marketing__component__secondary__button #{@font_class}"}
        data-size={@size}
        data-variant={@variant}
      >
        <%= render_slot(@inner_block) %>
      </button>
    <% end %>
    """
  end
end
