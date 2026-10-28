defmodule AtlasWeb.PaginationComponents do
  @moduledoc """
  Cursor-based pagination control rendered as Prev/Next buttons.

  Mirrors the pattern used in the Tuist dashboard for paginating external API
  results (e.g. Stripe) where total counts are not available cheaply. Pair with
  `AtlasWeb.Utilities.Query` to compose patch URLs from the current `@uri`.
  """
  use Phoenix.Component
  use Gettext, backend: AtlasWeb.Gettext
  use Noora

  alias AtlasWeb.Utilities.Query

  attr :uri, URI, required: true, doc: "The current request URI; cursors are layered onto its query string."
  attr :has_previous_page, :boolean, required: true
  attr :has_next_page, :boolean, required: true
  attr :start_cursor, :string, default: nil, doc: "Cursor used to navigate to the previous page."
  attr :end_cursor, :string, default: nil, doc: "Cursor used to navigate to the next page."
  attr :before_param, :string, default: "before", doc: "Query parameter used for previous-page cursors."
  attr :after_param, :string, default: "after", doc: "Query parameter used for next-page cursors."

  def pagination(assigns) do
    ~H"""
    <div data-part="pagination">
      <.button
        variant="secondary"
        label={gettext("Prev")}
        disabled={not @has_previous_page}
        patch={
          @has_previous_page and
            "?#{@uri.query |> Query.drop(@after_param) |> Query.put(@before_param, @start_cursor)}"
        }
      >
        <:icon_left><.chevron_left /></:icon_left>
      </.button>
      <.button
        variant="secondary"
        label={gettext("Next")}
        disabled={not @has_next_page}
        patch={
          @has_next_page and
            "?#{@uri.query |> Query.drop(@before_param) |> Query.put(@after_param, @end_cursor)}"
        }
      >
        <:icon_right><.chevron_right /></:icon_right>
      </.button>
    </div>
    """
  end
end
