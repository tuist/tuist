defmodule TuistWeb.Marketing.MarketingHTML do
  use TuistWeb, :html

  import TuistWeb.Marketing.MarketingLayoutComponents
  import TuistWeb.Marketing.MarketingLogos

  embed_templates "marketing_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :cta_variant, :string, required: false, default: "light"
  attr :cta_href, :string, required: false
  attr :cta_target, :string, default: ""
  attr :cta_text, :string, required: false

  def home_highlight_card(assigns) do
    ~H"""
    <div class="marketing__home__section__highlights__item">
      <div class="marketing__home__section__highlights__item__main">
        <h3 class="font-xxl-strong marketing__home__section__highlights__item__main__title">
          <%= @title %>
        </h3>
        <p class="font-m marketing__home__section__highlights__item__main__subtitle">
          <%= @subtitle %>
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
          <%= raw(@cta_text) %>
        </.secondary_button>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :index, :integer, required: true
  attr :banner_color, :atom, values: [:lime, :pink, :blue, :violet]
  attr :collapsed, :boolean, default: true
  attr :features, :list, required: true
  attr :toggle_feature, :any, required: false
  slot :logo, required: true
  slot :description, required: true
  slot :illustration, required: true

  def home_feature(assigns) do
    assigns =
      assign(
        assigns,
        :toggle_feature,
        (assigns[:toggle_feature] || %JS{})
        |> JS.toggle_attribute({"data-collapsed", "false", "true"},
          to: ".marketing__home__section__features__feature[data-index=\"#{assigns[:index]}\"]"
        )
      )

    ~H"""
    <div
      class="marketing__home__section__features__feature"
      data-index={@index}
      data-collapsed={if @collapsed, do: "true", else: "false"}
    >
      <div
        class="marketing__home__section__features__feature__banner"
        data-color={@banner_color |> Atom.to_string()}
        phx-click={@toggle_feature}
      >
        <div class="marketing__home__section__features__feature__banner__title font-xl-strong">
          <%= @title %>
        </div>
        <div class="marketing__home__section__features__feature__banner__index font-xl-strong">
          <%= "0#{@index}" %>
        </div>
      </div>

      <div class="marketing__home__section__features__feature__main">
        <div class="marketing__home__section__features__feature__main__header">
          <div class="marketing__home__section__features__feature__main__header__logo">
            <%= render_slot(@logo) %>
          </div>
          <h2 class="marketing__home__section__features__feature__main__header__title font-xxxl-strong">
            <%= @title %>
          </h2>
        </div>

        <div class="marketing__home__section__features__feature__main__body">
          <div class="marketing__home__section__features__feature__main__body__description font-l-strong">
            <%= render_slot(@description) %>
          </div>
          <div class="marketing__home__section__features__feature__main__body__features">
            <h3 class="marketing__home__section__features__feature__main__body__features__title font-l-strong">
              <%= gettext("Features") %>
            </h3>
            <ul class="marketing__home__section__features__feature__main__body__features__list">
              <li
                :for={feature <- @features}
                class="marketing__home__section__features__feature__main__body__features__list__feature font-m"
              >
                <TuistWeb.Marketing.MarketingIcons.check_circle_icon class="marketing__home__section__features__feature__main__body__features__list__feature__icon" />
                <div><%= feature %></div>
              </li>
            </ul>
          </div>
        </div>

        <div class="marketing__home__section__features__feature__illustration">
          <%= render_slot(@illustration) %>
        </div>
      </div>
    </div>
    """
  end
end
