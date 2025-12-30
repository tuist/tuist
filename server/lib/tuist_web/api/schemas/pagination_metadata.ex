defmodule TuistWeb.API.Schemas.PaginationMetadata do
  @moduledoc """
  The schema for the pagination metadata.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    description: "Pagination metadata.",
    type: :object,
    properties: %{
      has_next_page: %Schema{
        type: :boolean,
        description: "Whether there are more pages available."
      },
      has_previous_page: %Schema{
        type: :boolean,
        description: "Whether there are previous pages available."
      },
      current_page: %Schema{
        type: :integer,
        description: "Current page number. Always `nil` when using cursor-based pagination."
      },
      page_size: %Schema{
        type: :integer,
        description: "Number of items per page."
      },
      total_count: %Schema{
        type: :integer,
        description: "Total number of items."
      },
      total_pages: %Schema{
        type: :integer,
        description: "Total number of pages. Always `nil` when using cursor-based pagination."
      }
    },
    required: [:has_next_page, :has_previous_page, :page_size, :total_count]
  })
end
