defmodule TuistWeb.Storybook.PaginationGroup do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.PaginationGroup.pagination_group/1

  def variations do
    [
      %Variation{
        id: :pagination_group,
        attributes: %{
          number_of_pages: 12,
          current_page: 2,
          page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
        }
      }
    ]
  end
end
