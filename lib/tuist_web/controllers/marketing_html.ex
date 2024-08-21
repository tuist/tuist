defmodule TuistWeb.MarketingHTML do
  use TuistWeb, :html

  import TuistWeb.MarketingLayoutComponents

  embed_templates "marketing_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :cta_variant, :string, required: false, default: "light"
  attr :cta_href, :string, required: false
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
          href={@cta_href}
        >
          <%= @cta_text %>
        </.secondary_button>
      </div>
    </div>
    """
  end

  attr :category, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :image_url, :string, required: true
  attr :href, :string, required: true

  def home_learn_more_card(assigns) do
    ~H"""
    <div class="font-xs-strong marketing__home__section__learn_more__cards__card__category">
      <%= @category %>
    </div>
    <div class="font-xl-strong marketing__home__section__learn_more__cards__card__title">
      <%= @title %>
    </div>
    <div class="font-m marketing__home__section__learn_more__cards__card__description">
      <%= @description %>
    </div>
    <div
      class="marketing__home__section__learn_more__cards__card__image"
      style={"background-image: url(#{@image_url}); background-size: cover; background-position: center;"}
    >
      <.primary_icon_button href={@href} />
    </div>
    """
  end
end
