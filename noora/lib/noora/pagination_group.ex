defmodule Noora.PaginationGroup do
  @moduledoc """
  Pagination group component for paginating with a defined set of pages. Do not use this component for cursor-based pagination.

  ## Example

  ```elixir
  <.pagination_group
    current_page={@current_page}
    number_of_pages={25}
    page_patch={fn page -> ~p"/products?page=\#{page}" end}
  />
  ```
  """
  use Phoenix.Component

  import Noora.Button
  import Noora.Icon

  attr(:current_page, :integer, required: true, doc: "The current page number.")
  attr(:number_of_pages, :integer, required: true, doc: "The number of pages to display.")

  attr(:page_patch, :fun,
    required: true,
    doc: "Get a patch for an individual page where the input is the index."
  )

  attr(:rest, :global)

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
      <%= for page <- pagination_items(@current_page, @number_of_pages) do %>
        <span :if={page == :ellipsis} size="large" data-part="ellipsis">
          ...
        </span>
        <.link
          :if={page != :ellipsis}
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

  # This method is heavily inspired by: https://github.com/chakra-ui/zag/blob/b7adf8e5f0acc1a83c8e1745ed9809ad598e3d4a/packages/machines/pagination/src/pagination.utils.ts
  defp pagination_items(current_page, number_of_pages) do
    sibling_count = 1
    total_page_numbers = min(2 * sibling_count + 5, number_of_pages)

    first_page_index = 1
    last_page_index = number_of_pages

    left_sibling_index = max(current_page - sibling_count, first_page_index)
    right_sibling_index = min(current_page + sibling_count, last_page_index)

    show_left_ellipsis = left_sibling_index > first_page_index + 1
    show_right_ellipsis = right_sibling_index < last_page_index - 1

    # 2 stands for one ellipsis and either first or last page
    item_count = total_page_numbers - 2

    cond do
      !show_left_ellipsis && show_right_ellipsis ->
        left_range = Enum.to_list(1..item_count)
        left_range ++ [:ellipsis, last_page_index]

      show_left_ellipsis && !show_right_ellipsis ->
        right_range = Enum.to_list((last_page_index - item_count + 1)..last_page_index)
        [first_page_index, :ellipsis | right_range]

      show_left_ellipsis && show_right_ellipsis ->
        middle_range = Enum.to_list(left_sibling_index..right_sibling_index)
        [first_page_index, :ellipsis] ++ middle_range ++ [:ellipsis, last_page_index]

      true ->
        first_page_index..last_page_index
    end
  end
end
