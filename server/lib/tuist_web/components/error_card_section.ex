defmodule TuistWeb.Components.ErrorCardSection do
  @moduledoc """
  What a card shows in place of data that failed to load.

  Reads as the table empty state the rest of the dashboard uses, so a failed
  load sits in the page rather than shouting over it.

  `error_state/1` is the state on its own, for a card section that already
  holds other content. `error_card_section/1` wraps it in a card section, for
  a card whose whole section is the error.
  """
  use TuistWeb, :html
  use Noora

  attr :title, :string, default: nil, doc: "The title of the error state"
  attr :subtitle, :string, default: nil, doc: "What the reader can do about it"
  attr :rest, :global

  def error_card_section(assigns) do
    ~H"""
    <div class="noora-card__section" data-error {@rest}>
      <.error_state title={@title} subtitle={@subtitle} />
    </div>
    """
  end

  attr :title, :string, default: nil, doc: "The title of the error state"
  attr :subtitle, :string, default: nil, doc: "What the reader can do about it"
  attr :rest, :global

  def error_state(assigns) do
    ~H"""
    <div data-error {@rest}>
      <.table_empty_state
        icon="alert_circle"
        title={@title || dgettext("dashboard", "Something went wrong")}
        subtitle={
          @subtitle ||
            dgettext("dashboard", "We couldn't load the data. Reload the page and try again.")
        }
      />
    </div>
    """
  end
end
