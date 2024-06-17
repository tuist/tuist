defmodule TuistCloudWeb.API.Schemas.OrganizationUsage do
  @moduledoc """
  A schema for an organization.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

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
