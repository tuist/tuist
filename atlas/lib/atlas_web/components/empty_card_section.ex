defmodule AtlasWeb.Components.EmptyCardSection do
  @moduledoc """
  Empty state for a Noora card section. Mirrors tuist/server's
  `TuistWeb.Components.EmptyCardSection`: a centered title with an
  illustration slot above it, sitting on a `.noora-card__section`
  marked `data-empty` so the Noora card override picks it up.
  """

  use Phoenix.Component

  import AtlasWeb.Components.EmptyStateBackground

  attr :title, :string, required: true
  attr :rest, :global
  slot :image, required: true

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
    </div>
    """
  end
end
