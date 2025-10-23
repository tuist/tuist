defmodule TuistWeb.Marketing.MarketingComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  use Noora

  import TuistWeb.CSP, only: [get_csp_nonce: 0]
  import TuistWeb.Marketing.MarketingIcons

  embed_templates "marketing_layout_components/*"

  attr :href, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def marketing_link(assigns) do
    rest = Map.get(assigns, :rest, %{})
    href = assigns.href || Map.get(rest, :href) || ""
    local = String.starts_with?(href, "/")

    href =
      if local do
        case Gettext.get_locale() do
          "en" -> href
          locale -> "/#{locale}#{href}"
        end
      else
        href
      end

    assigns = assign(assigns, :rest, Map.put(rest, :href, href))

    ~H"""
    <Phoenix.Component.link {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  attr :key, :string, required: true
  attr :title, :string, required: true
  attr :href, :string, default: nil
  attr :children, :list, default: []
  attr :current_path, :string, required: true

  def marketing_mobile_menu_dropdown(assigns) do
    assigns =
      assign(assigns, :selector, ".marketing__header__bar__mobile__menu__main__dropdown[data-key=\"#{assigns[:key]}\"]")

    ~H"""
    <div
      class="marketing__header__bar__mobile__menu__main__dropdown"
      data-collapsed="true"
      data-key={@key}
    >
      <div
        class="marketing__header__bar__mobile__menu__main__dropdown__header"
        data-current={"#{@current_path == @href}"}
        phx-click={
          if(length(@children) > 0,
            do: JS.toggle_attribute({"data-collapsed", "true", "false"}, to: @selector),
            else: nil
          )
        }
      >
        <%= if length(@children) > 0 do %>
          <div class="marketing__header__bar__mobile__menu__main__dropdown__header__title font-xxl">
            {@title}
          </div>
        <% else %>
          <.marketing_link
            href={@href}
            class="marketing__header__bar__mobile__menu__main__dropdown__header__title font-xxl"
          >
            {@title}
          </.marketing_link>
        <% end %>
        <%= if length(@children) > 0 do %>
          <.plus_icon class="marketing__header__bar__mobile__menu__main__dropdown__header__icon" />
        <% end %>
      </div>

      <div class="marketing__header__bar__mobile__menu__main__dropdown__header__children">
        <.marketing_link
          :for={child <- @children}
          href={child.href}
          data-current={"#{@current_path == child.href}"}
          class="font-xl marketing__header__bar__mobile__menu__main__dropdown__header__children__child"
        >
          {child.title}
        </.marketing_link>
      </div>
    </div>
    """
  end

  attr :size, :integer, default: 72
  attr :class, :string, default: ""

  def marketing_shell(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 74 76"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M69.4048 53.2041C65.6096 56.1454 61.5546 58.7006 57.2935 60.7017C63.7193 53.0401 68.86 43.8299 72.781 35.2917C71.5508 32.7623 70.0635 30.3872 68.362 28.1924L68.2964 28.1612C64.3432 36.0193 59.7594 43.6362 54.1877 50.3643C53.513 51.1623 52.8249 51.9563 52.1221 52.7407C56.347 40.0635 58.9455 26.9351 60.9361 13.7905C58.92 12.2581 56.7567 10.9114 54.4662 9.78149C52.4153 20.272 49.8677 30.665 46.6093 40.7165C45.1889 45.071 43.6199 49.3631 41.8341 53.4737L40.5985 0.227168C39.4124 0.117426 38.2129 0.0632324 37 0.0632324C35.7871 0.0632324 34.5877 0.116071 33.4016 0.227168L32.1646 53.4899C30.3573 49.3468 28.8272 45.0452 27.3894 40.7179C24.131 30.665 21.5834 20.272 19.5325 9.78285C17.242 10.9128 15.0786 12.2595 13.0625 13.7918C15.0545 26.9459 17.6557 40.0852 21.886 52.7705C21.1818 51.9834 20.4897 51.1826 19.811 50.3657C14.2406 43.6376 9.65553 36.0206 5.70232 28.1626L5.63672 28.1937C3.93121 30.3926 2.4439 32.7717 1.21363 35.3026C2.51753 38.1681 3.90979 40.997 5.41048 43.7879C8.60732 49.5081 12.3249 55.4314 16.7279 60.7153C12.4575 58.7115 8.39581 56.1536 4.59387 53.2054C3.16814 55.2146 1.91913 57.3594 0.873596 59.6246C20.2072 81.3725 53.7861 81.3766 73.1238 59.6246C72.0769 57.3594 70.8292 55.2146 69.4035 53.2054L69.4048 53.2041Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  slot :inner_block, required: false

  attr :class, :string, default: ""
  attr :flavor, :string, values: ["primary", "secondary"], default: "primary"
  attr :href, :string, required: false
  attr :rest, :global

  def home_more_link(assigns) do
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
    <.marketing_link
      class={"marketing__component__link #{@font_class} #{@class}"}
      data-flavor={@flavor}
      href={assigns[:href]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.marketing_link>
    """
  end

  attr :size, :string, default: "medium", values: ["medium"]
  attr :href, :string, required: false
  attr :rest, :global
  attr :target, :string, required: false

  def primary_icon_button(assigns) do
    ~H"""
    <%= if assigns[:href] do %>
      <.marketing_link
        class="marketing__component__primary__icon__button"
        href={@href}
        target={assigns[:target]}
        {@rest}
      >
        <.icon_arrow_narrow_right />
      </.marketing_link>
    <% else %>
      <button {@rest} class="marketing__component__primary__icon__button">
        <.icon_arrow_narrow_right />
      </button>
    <% end %>
    """
  end

  attr :size, :string, required: true, values: ["big", "medium", "small"]
  attr :href, :string, required: false
  attr :class, :string, default: ""
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

    assigns = assign(assigns, :font_class, font_class)

    ~H"""
    <%= if assigns[:href] do %>
      <a
        href={assigns[:href]}
        target={assigns[:target]}
        {@rest}
        class={"marketing__component__primary__button #{@font_class} #{@class}"}
        data-size={@size}
      >
        {render_slot(@inner_block)}
      </a>
    <% else %>
      <button
        {@rest}
        class={"marketing__component__primary__button #{@font_class} #{@class}"}
        data-size={@size}
      >
        {render_slot(@inner_block)}
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

    assigns = assign(assigns, :font_class, font_class)

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
        {render_slot(@inner_block)}
      </a>
    <% else %>
      <button
        {@rest}
        class={"marketing__component__secondary__button #{@font_class}"}
        data-size={@size}
        data-variant={@variant}
      >
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true

  def footer_section(assigns) do
    ~H"""
    <div class="marketing__footer__main__menus__menu">
      <h4 class="marketing__footer__main__menus__menu_title font-xxs-strong">
        {@title}
      </h4>
      <div class="marketing__footer__main__menus__menu_links">
        <.marketing_link
          :for={item <- @items}
          href={item.href}
          class="marketing__footer__main__menus__menu_link font-xxs"
          target={Map.get(item, :target, nil)}
        >
          {item.text}
        </.marketing_link>
      </div>
    </div>
    """
  end

  attr :style, :string, default: ""
  attr :class, :string, default: ""
  def developers_docs_artwork(assigns)

  attr :current_path, :string, required: true
  def header(assigns)

  attr :category, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :image_url, :string, required: false
  attr :href, :string, required: true
  attr :class, :string, required: false

  def more_card(assigns) do
    ~H"""
    <div class={["marketing__component__more_card", @class]}>
      <.more_card_content
        category={@category}
        title={@title}
        description={@description}
        image_url={assigns[:image_url]}
        href={@href}
      />
    </div>
    """
  end

  attr :category, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :image_url, :string, required: false
  attr :href, :string, required: true

  def more_card_content(assigns) do
    ~H"""
    <div class="font-xs-strong marketing__component__more_card__content__category">
      {@category}
    </div>
    <.marketing_link
      class="font-xl-strong marketing__component__more_card__content__title"
      href={@href}
    >
      {@title}
    </.marketing_link>
    <div class="font-m marketing__component__more_card__content__description">
      {@description}
    </div>
    <% style =
      if(is_nil(assigns[:image_url]),
        do: "",
        else:
          "background-image: url(#{assigns[:image_url]}); background-size: cover; background-position: center;"
      ) %>
    <div class="marketing__component__more_card__content__image" style={style} nonce={get_csp_nonce()}>
      <.primary_icon_button href={@href} />
    </div>
    """
  end

  def header_background(assigns) do
    ~H"""
    <picture data-part="header-background">
      <source media="(max-width: 1024px)" srcset={~p"/images/hero-background-sm.webp"} />
      <img src={~p"/images/hero-background.webp"} alt="" />
    </picture>
    """
  end

  attr :popular, :boolean, default: false
  attr :name, :string, required: true
  attr :description, :string, required: true
  attr :price, :string, required: true
  attr :cta, :any, required: true
  attr :features, :list, required: true
  attr :badges, :list, required: true
  attr :price_frequency, :string, required: false

  def pricing_plan_plan_card(assigns) do
    ~H"""
    <div class="marketing__pricing__plans__plan" data-popular={@popular}>
      <div class="marketing__pricing__plans__plan__badge">
        {dgettext("marketing", "Most popular")}
      </div>
      <h2 class="marketing__pricing__plans__plan__name">
        {@name}
      </h2>
      <p class="marketing__pricing__plans__plan__description">
        {@description}
      </p>
      <div class="marketing__pricing__plans__plan__price">
        {@price}
        <span
          :if={not is_nil(assigns[:price_frequency])}
          class="marketing__pricing__plans__plan__price__frequency"
        >
          {@price_frequency}
        </span>
      </div>
      <%= case @cta do %>
        <% {:primary, text, href} -> %>
          <.primary_button href={href} size="big">
            {text}
          </.primary_button>
        <% {:secondary, text, href} -> %>
          <.secondary_button href={href} size="big" variant="light">
            {text}
          </.secondary_button>
      <% end %>
      <div class="marketing__pricing__plans__plan__cta__separator"></div>
      <ul class="marketing__pricing__plans__plan__features">
        <li :for={{title, description} <- @features} class="marketing__pricing__plans__plan__feature">
          <TuistWeb.Marketing.MarketingIcons.check_circle_icon class="marketing__pricing__plans__plan__feature__icon" />
          <div class="marketing__pricing__plans__plan__feature__content">
            <span class="marketing__pricing__plans__plan__feature__content__title">
              {title}
            </span>
            <span class="marketing__pricing__plans__plan__feature__content__description">
              {description}
            </span>
          </div>
        </li>
      </ul>
      <div class="marketing__pricing__plans__plan__bottom_badges">
        <div :for={badge <- @badges} class="marketing__pricing__plans__plan__bottom_badges__badge">
          {badge}
        </div>
      </div>
    </div>
    """
  end
end
