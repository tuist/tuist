defmodule TuistWeb.API.Schemas.OrganizationUsage do
  @moduledoc """
  A schema for an organization.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "The usage of an organization.",
    properties: %{
      current_month_remote_cache_hits: %Schema{
        type: :number,
        description: "The number of remote cache hits in the current month"
      }
    },
    required: [:current_month_remote_cache_hits]
  })
end
