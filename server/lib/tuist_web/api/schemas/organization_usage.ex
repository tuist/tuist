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
      },
      current_month_llm_tokens: %Schema{
        type: :object,
        description: "The number of LLM tokens used in the current month (input, output, and total)",
        properties: %{
          input: %Schema{type: :number, description: "Total input tokens month-to-date"},
          output: %Schema{type: :number, description: "Total output tokens month-to-date"},
          total: %Schema{type: :number, description: "Total tokens month-to-date"}
        },
        required: [:input, :output, :total]
      },
      current_month_compute_unit_minutes: %Schema{
        type: :number,
        description: "The number of compute unit minutes in the current month"
      }
    },
    required: [
      :current_month_remote_cache_hits,
      :current_month_llm_tokens,
      :current_month_compute_unit_minutes
    ]
  })
end
