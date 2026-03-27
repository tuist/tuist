defmodule TuistWeb.Storybook.PaginationGroup do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.PaginationGroup.pagination_group/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic pagination scenarios with different page positions",
        variations: [
          %Variation{
            id: :first_page,
            attributes: %{
              id: "pagination-first-page",
              number_of_pages: 12,
              current_page: 1,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :middle_page,
            attributes: %{
              id: "pagination-middle-page",
              number_of_pages: 12,
              current_page: 6,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :last_page,
            attributes: %{
              id: "pagination-last-page",
              number_of_pages: 12,
              current_page: 12,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :second_page,
            attributes: %{
              id: "pagination-second-page",
              number_of_pages: 12,
              current_page: 2,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          }
        ]
      },
      %VariationGroup{
        id: :page_counts,
        description: "Different total page counts showing ellipsis behavior",
        variations: [
          %Variation{
            id: :few_pages,
            attributes: %{
              id: "pagination-few-pages",
              number_of_pages: 5,
              current_page: 3,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :many_pages,
            attributes: %{
              id: "pagination-many-pages",
              number_of_pages: 50,
              current_page: 25,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :very_many_pages,
            attributes: %{
              id: "pagination-very-many",
              number_of_pages: 999,
              current_page: 500,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special scenarios",
        variations: [
          %Variation{
            id: :single_page,
            attributes: %{
              id: "pagination-single-page",
              number_of_pages: 1,
              current_page: 1,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :two_pages_first,
            attributes: %{
              id: "pagination-two-pages-first",
              number_of_pages: 2,
              current_page: 1,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :two_pages_last,
            attributes: %{
              id: "pagination-two-pages-last",
              number_of_pages: 2,
              current_page: 2,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :near_beginning,
            attributes: %{
              id: "pagination-near-beginning",
              number_of_pages: 20,
              current_page: 3,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          },
          %Variation{
            id: :near_end,
            attributes: %{
              id: "pagination-near-end",
              number_of_pages: 20,
              current_page: 18,
              page_patch: {:eval, ~s|fn page -> "?page=\#{page}" end|}
            }
          }
        ]
      }
    ]
  end
end
