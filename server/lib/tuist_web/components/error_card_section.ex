defmodule TuistWeb.Components.ErrorCardSection do
  @moduledoc """
  What a card shows in place of data that failed to load.

  `error_state/1` is the alert on its own, for a card section that already
  holds other content. `error_card_section/1` wraps it in a card section, for
  a card whose whole section is the error.
  """
  use TuistWeb, :html
  use Noora

  attr :title, :string, default: nil, doc: "The title of the error state"
  attr :description, :string, default: nil, doc: "What the reader can do about it"
  attr :rest, :global

  def error_card_section(assigns) do
    ~H"""
    <div class="noora-card__section" data-error {@rest}>
      <.error_state title={@title} description={@description} />
    </div>
    """
  end

  attr :title, :string, default: nil, doc: "The title of the error state"
  attr :description, :string, default: nil, doc: "What the reader can do about it"
  attr :rest, :global

  def error_state(assigns) do
    ~H"""
    <.alert
      status="error"
      size="large"
      title={@title || dgettext("dashboard", "Something went wrong")}
      description={
        @description ||
          dgettext("dashboard", "We couldn't load this data. Reload the page to try again.")
      }
      data-error
      {@rest}
    />
    """
  end
end
