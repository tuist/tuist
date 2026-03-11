defmodule Noora.Card do
  @moduledoc """
  A card component, used to separate content into sections.

  ## Example

  ```elixir
  <.card icon="layers" title="Overview">
    <.card_section>
      <p>Content goes here</p>
    </.card_section>
  </.card>
  ```
  """
  use Phoenix.Component

  import Noora.Icon
  import Noora.Utils

  attr(:icon, :string, required: true, doc: "The icon to display in the card.")
  attr(:title, :string, required: true, doc: "The title of the card.")
  attr(:rest, :global)

  slot(:actions,
    required: false,
    doc: "Slots for actions to be displayed in the card. Rendered to the right of the title."
  )

  slot(:inner_block, required: true)

  @doc """
  The main card container.
  """
  def card(assigns) do
    ~H"""
    <div class="noora-card" {@rest}>
      <div data-part="header">
        <div data-part="icon-with-title">
          <div data-part="icon">
            <.icon name={@icon} />
          </div>
          <span data-part="title">{@title}</span>
        </div>
        <div :if={has_slot_content?(@actions, assigns)} data-part="actions">
          {render_slot(@actions)}
        </div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:class, :string, default: "", doc: "The class to apply to the card section.")
  attr(:rest, :global)
  slot(:inner_block, required: true)

  @doc """
  A generic wrapper around a piece of content to be displayed in a card.
  Each card can contain multiple content sections.
  """
  def card_section(assigns) do
    ~H"""
    <div class={"noora-card__section " <> @class} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
