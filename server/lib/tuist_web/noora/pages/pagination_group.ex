defmodule TuistWeb.Noora.Pages.PaginationGroup do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Pagination group",
    description: "Moves between the pages of a list or table with a known number of pages.",
    components: [{Noora.PaginationGroup, :pagination_group}],
    guidelines: [
      "Use a pagination group when you know the total number of pages. It does not fit cursor-based pagination, where the total is unknown.",
      "Pass `page_patch` a function that takes a page number and returns the path to that page, usually the current query with the page parameter replaced.",
      "Name the page parameter after the list it paginates, such as `test-runs-page`, so several paginated lists can share a page.",
      "Render the group only when there is more than one page.",
      "The previous and next buttons are disabled on the first and last page. Long ranges collapse into ellipses around the current page."
    ]

  example "Default",
    description: "Pages before and after the current one, with the first and last page always in reach." do
    ~H"""
    <.pagination_group
      current_page={1}
      number_of_pages={12}
      page_patch={fn page -> "?test-runs-page=" <> Integer.to_string(page) end}
    />
    """
  end

  example "Middle page", description: "Away from the edges, ellipses replace the pages on both sides." do
    ~H"""
    <.pagination_group
      current_page={6}
      number_of_pages={12}
      page_patch={fn page -> "?test-runs-page=" <> Integer.to_string(page) end}
    />
    """
  end

  example "Last page", description: "The next button is disabled on the last page." do
    ~H"""
    <.pagination_group
      current_page={12}
      number_of_pages={12}
      page_patch={fn page -> "?test-runs-page=" <> Integer.to_string(page) end}
    />
    """
  end

  example "Few pages", description: "When the current page and its neighbors reach both ends, no ellipsis is needed." do
    ~H"""
    <.pagination_group
      current_page={3}
      number_of_pages={5}
      page_patch={fn page -> "?test-runs-page=" <> Integer.to_string(page) end}
    />
    """
  end
end
