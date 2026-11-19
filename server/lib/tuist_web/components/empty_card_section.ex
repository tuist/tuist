defmodule TuistWeb.Components.EmptyCardSection do
  @moduledoc """
    A LiveComponent that renders an empty card section.
  """
  use TuistWeb, :live_component
  use Noora

  import TuistWeb.Components.EmptyStateBackground

  attr :title, :string, required: true, doc: "The title of the empty card section"
  attr :description, :string, default: nil, doc: "An optional sentence under the title"
  attr :get_started_href, :string, default: nil, doc: "The Get started link"
  attr :rest, :global
  slot :image, required: true
  slot :actions, doc: "Optional links under the title, beside the Get started link"

  def empty_card_section(assigns) do
    ~H"""
    <div class="noora-card__section" data-empty {@rest}>
      <div data-part="background">
        <.empty_state_background />
      </div>
      <div data-part="image">
        {render_slot(@image)}
      </div>
      <span data-part="title">{@title}</span>
      <span :if={@description} data-part="description">{@description}</span>
      {render_slot(@actions)}
      <.link_button
        :if={@get_started_href}
        target="_blank"
        href={@get_started_href}
        label={dgettext("dashboard", "Get started")}
        size="medium"
        underline
      >
        <:icon_right><.external_link /></:icon_right>
      </.link_button>
    </div>
    """
  end
end
