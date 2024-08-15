defmodule TuistWeb.MarketingHTML do
  use TuistWeb, :html

  import TuistWeb.MarketingLayoutComponents

  embed_templates "marketing_html/*"

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
