defmodule TuistWeb.Marketing.MarketingHomeComponents do
  @moduledoc ~S"""
  A collection of components that are used in the marketing home page.
  """
  use TuistWeb, :live_component

  import TuistWeb.Marketing.MarketingComponents

  embed_templates "marketing_home_components/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :cta_variant, :string, required: false, default: "light"
  attr :cta_href, :string, required: false
  attr :cta_target, :string, default: ""
  attr :cta_text, :string, required: false

  def highlight_card(assigns) do
    ~H"""
    <div class="marketing__home__section__highlights__item">
      <div class="marketing__home__section__highlights__item__main">
        <h3 class="font-xxl-strong marketing__home__section__highlights__item__main__title">
          {@title}
        </h3>
        <p class="font-m marketing__home__section__highlights__item__main__subtitle">
          {@subtitle}
        </p>
      </div>
      <div
        :if={not is_nil(Map.get(assigns, :cta_text))}
        class="marketing__home__section__highlights__item__footer"
      >
        <.secondary_button
          :if={not is_nil(Map.get(assigns, :cta_text))}
          size="medium"
          variant={@cta_variant}
          target={@cta_target}
          href={@cta_href}
        >
          {raw(@cta_text)}
        </.secondary_button>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :description, :string, required: true
  attr :requires_projects, :boolean, default: false
  attr :id, :string, required: true
  attr :traits, :list, default: []
  slot :inner_block, required: false
  slot :logo, required: true

  def feature(assigns) do
    ~H"""
    <section class="marketing__home__section__features__feature" id={@id}>
      <div class="marketing__home__section__features__feature__side">
        {render_slot(@logo, %{class: "marketing__home__section__features__feature__side__logo"})}
      </div>
      <div class="marketing__home__section__features__feature__main">
        <h3 class="marketing__home__section__features__feature__title">
          {render_slot(@logo, %{class: "marketing__home__section__features__feature__title__logo"})}
          <span>{@name}</span>
          <%= if @requires_projects do %>
            <span class="marketing__home__section__features__feature__title__badge">
              {dgettext("marketing", "Requires a generated project")}
            </span>
          <% end %>
        </h3>
        <p class="marketing__home__section__features__feature__description">
          {@description}
        </p>
        <div class="marketing__home__section__features__feature__traits">
          <div
            :for={trait <- @traits}
            class="marketing__home__section__features__feature__traits__trait"
          >
            <TuistWeb.Marketing.MarketingIcons.check_circle_icon
              size={32}
              class="marketing__home__section__features__feature__traits__trait__icon"
            />
            <span>
              {trait}
            </span>
          </div>
        </div>
        <div class="marketing__home__section__features__feature__main">
          {render_slot(@inner_block)}
        </div>
        <div class="marketing__home__section__features__feature__main__divider" />
      </div>
    </section>
    """
  end

  slot :inner_block, required: true
  attr :terminal_id, :string, required: true
  attr :rest, :global

  def terminal(assigns) do
    ~H"""
    <div class="marketing__home__terminal" {@rest}>
      <div class="marketing__home__terminal__bar">
        <div class="marketing__home__terminal__bar__close_button" />
        <div class="marketing__home__terminal__bar__minimize_button" />
        <div class="marketing__home__terminal__bar__maximize_button" />
      </div>
      <div class="marketing__home__terminal__main">
        <div class="font-mono marketing__home__terminal__main__prompt" id={@terminal_id}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
