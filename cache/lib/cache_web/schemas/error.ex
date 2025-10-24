defmodule CacheWeb.Schemas.Error do
  @moduledoc """
  Error response schema
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Error",
    description: "Error response",
    type: :object,
    properties: %{
      message: %Schema{type: :string, description: "Error message"}
    },
    required: [:message],
    example: %{
      message: "Resource not found"
    }
  })
end
