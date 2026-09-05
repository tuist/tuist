defmodule TuistWeb.Components.ErrorCardSection do
  @moduledoc """
  A card section shown in place of data that failed to load.
  """
  use TuistWeb, :html
  use Noora

  attr :title, :string, default: nil, doc: "The title of the error card section"
  attr :description, :string, default: nil, doc: "What the reader can do about it"
  attr :rest, :global

  def error_card_section(assigns) do
    ~H"""
    <div class="noora-card__section" data-error {@rest}>
      <.alert
        status="error"
        size="large"
        title={@title || dgettext("dashboard", "Something went wrong")}
        description={
          @description ||
            dgettext("dashboard", "We couldn't load this data. Reload the page to try again.")
        }
      />
    </div>
    """
  end
end
