defmodule TuistWeb.MarketingLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  import TuistWeb.MarketingIcons

  embed_templates "marketing_layout_components/*"

  slot :inner_block, required: true

  def primary_small_button(assigns) do
    ~H"""
    <a class="marketing__component__primary__small__button font-xxs-strong">
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  attr :size, :atom, required: true, values: [:big, :medium, :small]
  attr :variant, :atom, required: true, values: [:light, :dark]
  attr :href, :string, required: false
  attr :target, :string, required: false
  attr :rest, :global
  slot :inner_block, required: false

  def secondary_button(assigns) do
    font_class =
      case assigns[:size] do
        :big -> "font-l-strong"
        :medium -> "font-m-strong"
        :small -> "font-xs-strong"
      end

    assigns = assigns |> assign(:font_class, font_class)

    ~H"""
    <%= if @href do %>
      <a
        href={assigns[:href]}
        target={assigns[:target]}
        {@rest}
        class={"marketing__component__secondary__button #{@font_class}"}
        data-size={Atom.to_string(@size)}
        data-variant={Atom.to_string(@variant)}
      >
        <%= render_slot(@inner_block) %>
      </a>
    <% else %>
      <button
        {@rest}
        class={"marketing__component__secondary__button #{@font_class}"}
        data-size={Atom.to_string(@size)}
        data-variant={Atom.to_string(@variant)}
      >
        <%= render_slot(@inner_block) %>
      </button>
    <% end %>
    """
  end
end
