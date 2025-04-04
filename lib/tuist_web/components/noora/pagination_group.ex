defmodule TuistWeb.Noora.PaginationGroup do
  @moduledoc """
  Pagination group component for paginating with a defined set of pages. Do not use this component for cursor-based pagination.
  """
  use Phoenix.Component
  import TuistWeb.Noora.Button
  import TuistWeb.Noora.Icon

  attr :current_page, :integer, required: true, doc: "The current page number."
  attr :number_of_pages, :integer, required: true, doc: "The number of pages to display."

  attr :page_patch, :fun,
    required: true,
    doc: "Get a patch for an individual page where the input is the index."

  attr :rest, :global

  def pagination_group(assigns) do
    ~H"""
    <div class="noora-pagination-group" {@rest}>
      <.neutral_button
        size="large"
        disabled={@current_page == 1}
        patch={@current_page != 1 and @page_patch.(@current_page - 1)}
      >
        <.chevron_left />
      </.neutral_button>
      <%= for page <- 1..@number_of_pages do %>
        <.link
          patch={@page_patch.(page)}
          data-part="page-button"
          data-selected={@current_page == page}
        >
          <span data-part="label">
            {page}
          </span>
        </.link>
      <% end %>

      <.neutral_button
        size="large"
        disabled={@current_page == @number_of_pages}
        patch={@current_page != @number_of_pages and @page_patch.(@current_page + 1)}
      >
        <.chevron_right />
      </.neutral_button>
    </div>
    """
  end
end
