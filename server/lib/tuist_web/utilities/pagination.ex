defmodule TuistWeb.Utilities.Pagination do
  @moduledoc """
  Shared helpers for the simple in-memory pagination used by the ops LiveViews.

  Each view keeps its own `@page_size` and its own data-shaped
  `filtered_*`/`paginated_*` wrappers, but the page-count math and the query
  parameter parsing live here so they cannot drift out of sync.
  """

  @doc """
  Parses a page query parameter into a positive integer, defaulting to 1 for
  missing or malformed values.
  """
  def parse_page(nil), do: 1

  def parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  @doc """
  Total number of pages needed to hold `count` items at `page_size` per page,
  never less than one.
  """
  def total_pages(count, page_size) when page_size > 0 do
    count
    |> Kernel./(page_size)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  @doc """
  Clamps the requested page to the available range.
  """
  def current_page(page, total_pages), do: min(page, total_pages)

  @doc """
  Returns the slice of `items` that belongs to the 1-indexed `page`.
  """
  def paginate(items, page, page_size) do
    Enum.slice(items, (page - 1) * page_size, page_size)
  end
end
